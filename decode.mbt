///|
fn channels_for_color_type(color_type : Byte) -> Int {
  match color_type.to_int() {
    0 => 1
    2 => 3
    3 => 1
    4 => 2
    6 => 4
    _ => 0
  }
}

///|
fn bits_per_pixel(bit_depth : Byte, color_type : Byte) -> Int {
  bit_depth.to_int() * channels_for_color_type(color_type)
}

///|
fn absolute(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
fn paeth_predictor(left : Int, above : Int, upper_left : Int) -> Int {
  let estimate = left + above - upper_left
  let left_distance = absolute(estimate - left)
  let above_distance = absolute(estimate - above)
  let diagonal_distance = absolute(estimate - upper_left)
  if left_distance <= above_distance && left_distance <= diagonal_distance {
    left
  } else if above_distance <= diagonal_distance {
    above
  } else {
    upper_left
  }
}

///|
fn unfilter_scanlines(
  inflated : Bytes,
  row_bytes : Int,
  bytes_per_pixel : Int,
  height : Int,
) -> Result[Array[Byte], DecodeError] {
  let expected = (row_bytes + 1) * height
  if inflated.length() != expected {
    return Err(InvalidInflatedSize(expected, inflated.length()))
  }
  let output = Array::make(row_bytes * height, b'\x00')
  for row = 0; row < height; row = row + 1 {
    let source_start = row * (row_bytes + 1)
    let output_start = row * row_bytes
    let filter = inflated.unsafe_get(source_start)
    if filter.to_int() > 4 {
      return Err(InvalidFilter(filter, row))
    }
    for column = 0; column < row_bytes; column = column + 1 {
      let source = inflated.unsafe_get(source_start + 1 + column).to_int()
      let left = if column >= bytes_per_pixel {
        output[output_start + column - bytes_per_pixel].to_int()
      } else {
        0
      }
      let above = if row > 0 {
        output[output_start + column - row_bytes].to_int()
      } else {
        0
      }
      let upper_left = if row > 0 && column >= bytes_per_pixel {
        output[output_start + column - row_bytes - bytes_per_pixel].to_int()
      } else {
        0
      }
      let predictor = match filter.to_int() {
        0 => 0
        1 => left
        2 => above
        3 => (left + above) / 2
        4 => paeth_predictor(left, above, upper_left)
        _ => 0
      }
      output[output_start + column] = (source + predictor).to_byte()
    }
  }
  Ok(output)
}

///|
fn read_uint16_be(data : Bytes, offset : Int) -> Int {
  (data.unsafe_get(offset).to_int() << 8) | data.unsafe_get(offset + 1).to_int()
}

///|
priv struct ColorData {
  palette : Bytes?
  palette_alpha : Bytes?
  transparent_gray : Int?
  transparent_rgb : (Int, Int, Int)?
}

///|
fn copy_bytes(data : Bytes, offset : Int, length : Int) -> Bytes {
  let output : Array[Byte] = []
  output.reserve_capacity(length)
  for index = 0; index < length; index = index + 1 {
    output.push(data.unsafe_get(offset + index))
  }
  Bytes::from_array(output)
}

///|
fn parse_color_data(
  data : Bytes,
  info : PngInfo,
) -> Result[ColorData, DecodeError] {
  let mut seen_idat = false
  let mut seen_palette = false
  let mut seen_transparency = false
  let mut palette : Bytes? = None
  let mut palette_entries = 0
  let mut palette_alpha : Bytes? = None
  let mut transparent_gray : Int? = None
  let mut transparent_rgb : (Int, Int, Int)? = None
  for chunk in info.chunks {
    if chunk.kind == "IDAT" {
      seen_idat = true
    } else if chunk.kind == "PLTE" {
      if seen_idat {
        return Err(InvalidChunkOrder("PLTE"))
      }
      if seen_palette {
        return Err(DuplicatePalette)
      }
      seen_palette = true
      if chunk.length == 0 || chunk.length > 768 || chunk.length % 3 != 0 {
        return Err(InvalidPaletteLength(chunk.length))
      }
      if info.color_type == b'\x00' || info.color_type == b'\x04' {
        return Err(UnexpectedPalette(info.color_type))
      }
      palette_entries = chunk.length / 3
      if info.color_type == b'\x03' &&
        palette_entries > 1 << info.bit_depth.to_int() {
        return Err(PaletteTooLarge(palette_entries, info.bit_depth))
      }
      palette = Some(copy_bytes(data, chunk.data_offset, chunk.length))
    } else if chunk.kind == "tRNS" {
      if seen_idat {
        return Err(InvalidChunkOrder("tRNS"))
      }
      if seen_transparency {
        return Err(DuplicateTransparency)
      }
      seen_transparency = true
      if info.color_type == b'\x00' {
        if chunk.length != 2 {
          return Err(InvalidTransparency(info.color_type, chunk.length))
        }
        transparent_gray = Some(read_uint16_be(data, chunk.data_offset))
      } else if info.color_type == b'\x02' {
        if chunk.length != 6 {
          return Err(InvalidTransparency(info.color_type, chunk.length))
        }
        transparent_rgb = Some(
          (
            read_uint16_be(data, chunk.data_offset),
            read_uint16_be(data, chunk.data_offset + 2),
            read_uint16_be(data, chunk.data_offset + 4),
          ),
        )
      } else if info.color_type == b'\x03' {
        if !seen_palette || chunk.length == 0 || chunk.length > palette_entries {
          return Err(InvalidTransparency(info.color_type, chunk.length))
        }
        palette_alpha = Some(copy_bytes(data, chunk.data_offset, chunk.length))
      } else {
        return Err(InvalidTransparency(info.color_type, chunk.length))
      }
    }
  }
  if info.color_type == b'\x03' && !seen_palette {
    return Err(MissingPalette)
  }
  Ok({ palette, palette_alpha, transparent_gray, transparent_rgb, })
}

///|
fn packed_sample(
  scanlines : Array[Byte],
  row_start : Int,
  x : Int,
  bit_depth : Int,
) -> Int {
  let bit_offset = x * bit_depth
  let byte = scanlines[row_start + bit_offset / 8].to_int()
  let shift = 8 - bit_depth - bit_offset % 8
  (byte >> shift) & ((1 << bit_depth) - 1)
}

///|
fn scanline_uint16_be(scanlines : Array[Byte], offset : Int) -> Int {
  (scanlines[offset].to_int() << 8) | scanlines[offset + 1].to_int()
}

///|
fn convert_to_rgba(
  scanlines : Array[Byte],
  width : Int,
  height : Int,
  row_bytes : Int,
  bit_depth : Byte,
  color_type : Byte,
  color_data : ColorData,
) -> Result[Bytes, DecodeError] {
  let channels = channels_for_color_type(color_type)
  let depth = bit_depth.to_int()
  let pixel_count = width * height
  let rgba : Array[Byte] = []
  rgba.reserve_capacity(pixel_count * 4)
  for y = 0; y < height; y = y + 1 {
    let row_start = y * row_bytes
    for x = 0; x < width; x = x + 1 {
      if color_type == b'\x00' {
        let sample = if depth == 16 {
          scanline_uint16_be(scanlines, row_start + x * 2)
        } else if depth == 8 {
          scanlines[row_start + x].to_int()
        } else {
          packed_sample(scanlines, row_start, x, depth)
        }
        let gray = if depth == 16 {
          sample >> 8
        } else if depth == 8 {
          sample
        } else {
          sample * 255 / ((1 << depth) - 1)
        }
        let alpha = match color_data.transparent_gray {
          Some(transparent) =>
            if sample == transparent {
              b'\x00'
            } else {
              b'\xff'
            }
          None => b'\xff'
        }
        rgba.push(gray.to_byte())
        rgba.push(gray.to_byte())
        rgba.push(gray.to_byte())
        rgba.push(alpha)
      } else if color_type == b'\x03' {
        let index = if depth == 8 {
          scanlines[row_start + x].to_int()
        } else {
          packed_sample(scanlines, row_start, x, depth)
        }
        let palette = match color_data.palette {
          Some(value) => value
          None => return Err(MissingPalette)
        }
        let palette_offset = index * 3
        if palette_offset + 2 >= palette.length() {
          return Err(PaletteIndexOutOfRange(index, x, y))
        }
        rgba.push(palette.unsafe_get(palette_offset))
        rgba.push(palette.unsafe_get(palette_offset + 1))
        rgba.push(palette.unsafe_get(palette_offset + 2))
        let alpha = match color_data.palette_alpha {
          Some(values) =>
            if index < values.length() {
              values.unsafe_get(index)
            } else {
              b'\xff'
            }
          None => b'\xff'
        }
        rgba.push(alpha)
      } else {
        let bytes_per_sample = depth / 8
        let offset = row_start + x * channels * bytes_per_sample
        if color_type == b'\x02' {
          let red_sample = if depth == 16 {
            scanline_uint16_be(scanlines, offset)
          } else {
            scanlines[offset].to_int()
          }
          let green_sample = if depth == 16 {
            scanline_uint16_be(scanlines, offset + 2)
          } else {
            scanlines[offset + 1].to_int()
          }
          let blue_sample = if depth == 16 {
            scanline_uint16_be(scanlines, offset + 4)
          } else {
            scanlines[offset + 2].to_int()
          }
          let alpha = match color_data.transparent_rgb {
            Some((transparent_red, transparent_green, transparent_blue)) =>
              if red_sample == transparent_red &&
                green_sample == transparent_green &&
                blue_sample == transparent_blue {
                b'\x00'
              } else {
                b'\xff'
              }
            None => b'\xff'
          }
          rgba.push(
            (if depth == 16 { red_sample >> 8 } else { red_sample }).to_byte(),
          )
          rgba.push(
            (if depth == 16 { green_sample >> 8 } else { green_sample }).to_byte(),
          )
          rgba.push(
            (if depth == 16 { blue_sample >> 8 } else { blue_sample }).to_byte(),
          )
          rgba.push(alpha)
        } else if color_type == b'\x04' {
          let gray = scanlines[offset]
          let alpha_offset = if depth == 16 { offset + 2 } else { offset + 1 }
          rgba.push(gray)
          rgba.push(gray)
          rgba.push(gray)
          rgba.push(scanlines[alpha_offset])
        } else {
          let step = if depth == 16 { 2 } else { 1 }
          rgba.push(scanlines[offset])
          rgba.push(scanlines[offset + step])
          rgba.push(scanlines[offset + step * 2])
          rgba.push(scanlines[offset + step * 3])
        }
      }
    }
  }
  Ok(Bytes::from_array(rgba))
}

///|
fn adam7_passes() -> Array[(Int, Int, Int, Int)] {
  [
    (0, 0, 8, 8),
    (4, 0, 8, 8),
    (0, 4, 4, 8),
    (2, 0, 4, 4),
    (0, 2, 2, 4),
    (1, 0, 2, 2),
    (0, 1, 1, 2),
  ]
}

///|
fn adam7_extent(size : Int, start : Int, step : Int) -> Int {
  if size <= start {
    0
  } else {
    (size - start + step - 1) / step
  }
}

///|
fn adam7_inflated_size(width : Int, height : Int, pixel_bits : Int) -> Int? {
  let mut total = 0
  for pass in adam7_passes() {
    let (start_x, start_y, step_x, step_y) = pass
    let pass_width = adam7_extent(width, start_x, step_x)
    let pass_height = adam7_extent(height, start_y, step_y)
    if pass_width > 0 && pass_height > 0 {
      let row_bytes = (pass_width * pixel_bits + 7) / 8
      if row_bytes + 1 > (0x7fffffff - total) / pass_height {
        return None
      }
      total = total + (row_bytes + 1) * pass_height
    }
  }
  Some(total)
}

///|
fn decode_adam7(
  inflated : Bytes,
  width : Int,
  height : Int,
  pixel_bits : Int,
  bit_depth : Byte,
  color_type : Byte,
  color_data : ColorData,
) -> Result[Bytes, DecodeError] {
  let output = Array::make(width * height * 4, b'\x00')
  let filter_bytes_per_pixel = (pixel_bits + 7) / 8
  let mut inflated_offset = 0
  for pass in adam7_passes() {
    let (start_x, start_y, step_x, step_y) = pass
    let pass_width = adam7_extent(width, start_x, step_x)
    let pass_height = adam7_extent(height, start_y, step_y)
    if pass_width > 0 && pass_height > 0 {
      let row_bytes = (pass_width * pixel_bits + 7) / 8
      let pass_size = (row_bytes + 1) * pass_height
      let pass_inflated = copy_bytes(inflated, inflated_offset, pass_size)
      inflated_offset = inflated_offset + pass_size
      let scanlines = match
        unfilter_scanlines(
          pass_inflated, row_bytes, filter_bytes_per_pixel, pass_height,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let pass_pixels = match
        convert_to_rgba(
          scanlines, pass_width, pass_height, row_bytes, bit_depth, color_type, color_data,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      for pass_y = 0; pass_y < pass_height; pass_y = pass_y + 1 {
        let target_y = start_y + pass_y * step_y
        for pass_x = 0; pass_x < pass_width; pass_x = pass_x + 1 {
          let target_x = start_x + pass_x * step_x
          let source = (pass_y * pass_width + pass_x) * 4
          let target = (target_y * width + target_x) * 4
          output[target] = pass_pixels.unsafe_get(source)
          output[target + 1] = pass_pixels.unsafe_get(source + 1)
          output[target + 2] = pass_pixels.unsafe_get(source + 2)
          output[target + 3] = pass_pixels.unsafe_get(source + 3)
        }
      }
    }
  }
  Ok(Bytes::from_array(output))
}

///|
fn collect_idat(
  data : Bytes,
  info : PngInfo,
  max_compressed_size : Int,
) -> Result[Bytes, DecodeError] {
  let compressed : Array[Byte] = []
  for chunk in info.chunks {
    if chunk.kind == "IDAT" {
      if chunk.length > max_compressed_size - compressed.length() {
        return Err(CompressedDataTooLarge(max_compressed_size))
      }
      for index = 0; index < chunk.length; index = index + 1 {
        compressed.push(data.unsafe_get(chunk.data_offset + index))
      }
    }
  }
  if compressed.is_empty() {
    return Err(MissingIdatData)
  }
  Ok(Bytes::from_array(compressed))
}

///|
/// Decode a PNG into row-major RGBA8 pixels.
///
/// Every bit depth permitted by the PNG color type is supported. Sixteen-bit
/// channels are converted to RGBA8 by retaining the most significant byte.
/// `PLTE` palettes and applicable `tRNS` transparency are honored.
pub fn decode(data : Bytes) -> Result[DecodedImage, DecodeError] {
  decode_with_limits(data, default_decode_limits())
}

///|
/// Decode a PNG with caller-provided resource limits.
pub fn decode_with_limits(
  data : Bytes,
  limits : DecodeLimits,
) -> Result[DecodedImage, DecodeError] {
  if limits.max_chunk_size <= 0 ||
    limits.max_chunks <= 0 ||
    limits.max_compressed_size <= 0 ||
    limits.max_inflated_size <= 0 ||
    limits.max_pixels <= 0 {
    return Err(InvalidDecodeLimits)
  }
  let info = match
    inspect_with_limits(
      data,
      max_chunk_size=limits.max_chunk_size,
      max_chunks=limits.max_chunks,
    ) {
    Ok(value) => value
    Err(error) => return Err(InvalidContainer(error))
  }
  let channels = channels_for_color_type(info.color_type)
  if channels == 0 {
    return Err(UnsupportedColorType(info.color_type))
  }
  if info.interlace_method != b'\x00' && info.interlace_method != b'\x01' {
    return Err(UnsupportedInterlace(info.interlace_method))
  }
  for chunk in info.chunks {
    if chunk.is_critical &&
      chunk.kind != "IHDR" &&
      chunk.kind != "PLTE" &&
      chunk.kind != "IDAT" &&
      chunk.kind != "IEND" {
      return Err(UnsupportedCriticalChunk(chunk.kind))
    }
  }
  if info.width > 0x7fffffffU || info.height > 0x7fffffffU {
    return Err(ImageTooLarge(info.width, info.height, limits.max_pixels))
  }
  let width = info.width.reinterpret_as_int()
  let height = info.height.reinterpret_as_int()
  if height > limits.max_pixels || width > limits.max_pixels / height {
    return Err(ImageTooLarge(info.width, info.height, limits.max_pixels))
  }
  let pixel_count = width * height
  if pixel_count > 0x7fffffff / 4 {
    return Err(ImageTooLarge(info.width, info.height, limits.max_pixels))
  }
  let pixel_bits = bits_per_pixel(info.bit_depth, info.color_type)
  if pixel_bits == 0 || width > (0x7fffffff - 7) / pixel_bits {
    return Err(ImageTooLarge(info.width, info.height, limits.max_pixels))
  }
  let row_bytes = (width * pixel_bits + 7) / 8
  if row_bytes >= 0x7fffffff || row_bytes + 1 > 0x7fffffff / height {
    return Err(ImageTooLarge(info.width, info.height, limits.max_pixels))
  }
  let expected_inflated_size = if info.interlace_method == b'\x00' {
    (row_bytes + 1) * height
  } else {
    match adam7_inflated_size(width, height, pixel_bits) {
      Some(value) => value
      None =>
        return Err(ImageTooLarge(info.width, info.height, limits.max_pixels))
    }
  }
  if expected_inflated_size > limits.max_inflated_size {
    return Err(OutputLimitExceeded(limits.max_inflated_size))
  }

  let color_data = match parse_color_data(data, info) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let compressed = match collect_idat(data, info, limits.max_compressed_size) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let inflated = match
    inflate_zlib_with_limit(compressed, max_output_size=expected_inflated_size) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pixels = if info.interlace_method == b'\x00' {
    let filter_bytes_per_pixel = (pixel_bits + 7) / 8
    let scanlines = match
      unfilter_scanlines(inflated, row_bytes, filter_bytes_per_pixel, height) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match
      convert_to_rgba(
        scanlines,
        width,
        height,
        row_bytes,
        info.bit_depth,
        info.color_type,
        color_data,
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  } else {
    match
      decode_adam7(
        inflated,
        width,
        height,
        pixel_bits,
        info.bit_depth,
        info.color_type,
        color_data,
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  Ok({ width: info.width, height: info.height, pixels, })
}
