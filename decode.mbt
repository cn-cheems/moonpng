///|
fn channels_for_color_type(color_type : Byte) -> Int {
  match color_type.to_int() {
    0 => 1
    2 => 3
    4 => 2
    6 => 4
    _ => 0
  }
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
fn parse_transparency(
  data : Bytes,
  info : PngInfo,
) -> Result[(Int?, (Int, Int, Int)?), DecodeError] {
  let mut found = false
  let mut transparent_gray : Int? = None
  let mut transparent_rgb : (Int, Int, Int)? = None
  for chunk in info.chunks {
    if chunk.kind == "tRNS" {
      if found {
        return Err(DuplicateTransparency)
      }
      found = true
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
      } else {
        return Err(InvalidTransparency(info.color_type, chunk.length))
      }
    }
  }
  Ok((transparent_gray, transparent_rgb))
}

///|
fn convert_to_rgba(
  scanlines : Array[Byte],
  color_type : Byte,
  transparent_gray : Int?,
  transparent_rgb : (Int, Int, Int)?,
) -> Bytes {
  let channels = channels_for_color_type(color_type)
  let pixel_count = scanlines.length() / channels
  let rgba : Array[Byte] = []
  rgba.reserve_capacity(pixel_count * 4)
  for pixel = 0; pixel < pixel_count; pixel = pixel + 1 {
    let offset = pixel * channels
    if color_type == b'\x00' {
      let gray = scanlines[offset]
      let alpha = match transparent_gray {
        Some(sample) => if gray.to_int() == sample { b'\x00' } else { b'\xff' }
        None => b'\xff'
      }
      rgba.push(gray)
      rgba.push(gray)
      rgba.push(gray)
      rgba.push(alpha)
    } else if color_type == b'\x02' {
      let red = scanlines[offset]
      let green = scanlines[offset + 1]
      let blue = scanlines[offset + 2]
      let alpha = match transparent_rgb {
        Some((transparent_red, transparent_green, transparent_blue)) =>
          if red.to_int() == transparent_red &&
            green.to_int() == transparent_green &&
            blue.to_int() == transparent_blue {
            b'\x00'
          } else {
            b'\xff'
          }
        None => b'\xff'
      }
      rgba.push(red)
      rgba.push(green)
      rgba.push(blue)
      rgba.push(alpha)
    } else if color_type == b'\x04' {
      let gray = scanlines[offset]
      rgba.push(gray)
      rgba.push(gray)
      rgba.push(gray)
      rgba.push(scanlines[offset + 1])
    } else {
      rgba.push(scanlines[offset])
      rgba.push(scanlines[offset + 1])
      rgba.push(scanlines[offset + 2])
      rgba.push(scanlines[offset + 3])
    }
  }
  Bytes::from_array(rgba)
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
/// Decode a non-interlaced, 8-bit PNG into row-major RGBA8 pixels.
///
/// Color types 0 (grayscale), 2 (truecolor), 4 (grayscale with alpha), and 6
/// (truecolor with alpha) are supported. Grayscale and truecolor `tRNS`
/// transparency is honored.
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
  if info.bit_depth != b'\x08' {
    return Err(UnsupportedBitDepth(info.bit_depth))
  }
  let channels = channels_for_color_type(info.color_type)
  if channels == 0 {
    return Err(UnsupportedColorType(info.color_type))
  }
  if info.interlace_method != b'\x00' {
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
  if width > 0x7fffffff / channels {
    return Err(ImageTooLarge(info.width, info.height, limits.max_pixels))
  }
  let row_bytes = width * channels
  if row_bytes >= 0x7fffffff || row_bytes + 1 > 0x7fffffff / height {
    return Err(ImageTooLarge(info.width, info.height, limits.max_pixels))
  }
  let expected_inflated_size = (row_bytes + 1) * height
  if expected_inflated_size > limits.max_inflated_size {
    return Err(OutputLimitExceeded(limits.max_inflated_size))
  }

  let (transparent_gray, transparent_rgb) = match
    parse_transparency(data, info) {
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
  let scanlines = match
    unfilter_scanlines(inflated, row_bytes, channels, height) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    width: info.width,
    height: info.height,
    pixels: convert_to_rgba(
      scanlines,
      info.color_type,
      transparent_gray,
      transparent_rgb,
    ),
  })
}
