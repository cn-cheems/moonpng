///|
fn encode_append_bytes(output : Array[Byte], data : Bytes) -> Unit {
  for byte in data {
    output.push(byte)
  }
}

///|
fn encode_append_uint32_be(output : Array[Byte], value : UInt) -> Unit {
  output.push((value >> 24).to_byte())
  output.push((value >> 16).to_byte())
  output.push((value >> 8).to_byte())
  output.push(value.to_byte())
}

///|
fn encode_append_chunk(
  output : Array[Byte],
  kind : Bytes,
  payload : Bytes,
) -> Unit {
  encode_append_uint32_be(output, payload.length().reinterpret_as_uint())
  encode_append_bytes(output, kind)
  encode_append_bytes(output, payload)
  encode_append_uint32_be(output, crc32(kind + payload))
}

///|
fn encode_chunk_bytes(kind : Bytes, payload : Bytes) -> Bytes {
  let output : Array[Byte] = []
  encode_append_chunk(output, kind, payload)
  Bytes::from_array(output)
}

///|
fn encode_copy_range(data : Bytes, offset : Int, length : Int) -> Bytes {
  let output : Array[Byte] = []
  output.reserve_capacity(length)
  for index = 0; index < length; index = index + 1 {
    output.push(data.unsafe_get(offset + index))
  }
  Bytes::from_array(output)
}

///|
fn encode_stored_zlib(raw : Bytes) -> Bytes {
  let output : Array[Byte] = [b'\x78', b'\x01']
  let mut offset = 0
  while offset < raw.length() {
    let remaining = raw.length() - offset
    let block_length = if remaining > 65535 { 65535 } else { remaining }
    let is_final = offset + block_length == raw.length()
    output.push(if is_final { b'\x01' } else { b'\x00' })
    output.push(block_length.to_byte())
    output.push((block_length >> 8).to_byte())
    let inverse = block_length ^ 0xffff
    output.push(inverse.to_byte())
    output.push((inverse >> 8).to_byte())
    for index = 0; index < block_length; index = index + 1 {
      output.push(raw.unsafe_get(offset + index))
    }
    offset = offset + block_length
  }
  encode_append_uint32_be(output, adler32(raw))
  Bytes::from_array(output)
}

///|
fn encode_filter_code(strategy : FilterStrategy) -> Byte {
  match strategy {
    FilterNone => b'\x00'
    FilterSub => b'\x01'
    FilterUp => b'\x02'
    FilterAverage => b'\x03'
    FilterPaeth => b'\x04'
    FilterAdaptive => b'\x00'
  }
}

///|
fn encode_filter_row(
  row : Bytes,
  previous_row : Bytes?,
  bytes_per_pixel : Int,
  filter : Byte,
) -> Array[Byte] {
  let output = Array::make(row.length(), b'\x00')
  for column = 0; column < row.length(); column = column + 1 {
    let source = row.unsafe_get(column).to_int()
    let left = if column >= bytes_per_pixel {
      row.unsafe_get(column - bytes_per_pixel).to_int()
    } else {
      0
    }
    let above = match previous_row {
      Some(previous) => previous.unsafe_get(column).to_int()
      None => 0
    }
    let upper_left = match previous_row {
      Some(previous) =>
        if column >= bytes_per_pixel {
          previous.unsafe_get(column - bytes_per_pixel).to_int()
        } else {
          0
        }
      None => 0
    }
    let predictor = match filter.to_int() {
      0 => 0
      1 => left
      2 => above
      3 => (left + above) / 2
      4 => paeth_predictor(left, above, upper_left)
      _ => 0
    }
    output[column] = (source - predictor).to_byte()
  }
  output
}

///|
fn encode_filter_score(row : Array[Byte]) -> Int {
  let mut score = 0
  for byte in row {
    let value = byte.to_int()
    let contribution = if value < 128 { value } else { 256 - value }
    if score > 0x7fffffff - contribution {
      return 0x7fffffff
    }
    score = score + contribution
  }
  score
}

///|
fn encode_choose_filter(
  row : Bytes,
  previous_row : Bytes?,
  bytes_per_pixel : Int,
  strategy : FilterStrategy,
) -> (Byte, Array[Byte]) {
  if strategy != FilterAdaptive {
    let code = encode_filter_code(strategy)
    return (code, encode_filter_row(row, previous_row, bytes_per_pixel, code))
  }
  let mut best_code = b'\x00'
  let mut best_row = encode_filter_row(
    row, previous_row, bytes_per_pixel, best_code,
  )
  let mut best_score = encode_filter_score(best_row)
  for code_value = 1; code_value <= 4; code_value = code_value + 1 {
    let code = code_value.to_byte()
    let candidate = encode_filter_row(row, previous_row, bytes_per_pixel, code)
    let score = encode_filter_score(candidate)
    if score < best_score {
      best_code = code
      best_row = candidate
      best_score = score
    }
  }
  (best_code, best_row)
}

///|
fn encode_pixel_channels(format : PixelFormat) -> Int {
  match format {
    PixelGray8 => 1
    PixelGrayAlpha8 => 2
    PixelRgb8 => 3
    PixelRgba8 => 4
  }
}

///|
fn encode_color_type(format : PixelFormat) -> Byte {
  match format {
    PixelGray8 => b'\x00'
    PixelGrayAlpha8 => b'\x04'
    PixelRgb8 => b'\x02'
    PixelRgba8 => b'\x06'
  }
}

///|
fn encode_ihdr_payload(
  width : UInt,
  height : UInt,
  format : PixelFormat,
) -> Bytes {
  let ihdr : Array[Byte] = []
  encode_append_uint32_be(ihdr, width)
  encode_append_uint32_be(ihdr, height)
  ihdr.push(b'\x08')
  ihdr.push(encode_color_type(format))
  ihdr.push(b'\x00')
  ihdr.push(b'\x00')
  ihdr.push(b'\x00')
  Bytes::from_array(ihdr)
}

///|
fn encode_emit_idat_byte(
  payload : Array[Byte],
  limit : Int,
  emit : (Bytes) -> Unit,
  value : Byte,
) -> Unit {
  payload.push(value)
  if payload.length() == limit {
    emit(encode_chunk_bytes(b"IDAT", Bytes::from_array(payload)))
    payload.clear()
  }
}

///|
fn encode_update_adler(value : UInt, byte : Byte) -> UInt {
  let sum = value & 0xffffU
  let weighted = value >> 16
  let next_sum = (sum + byte.to_uint()) % 65521U
  let next_weighted = (weighted + next_sum) % 65521U
  (next_weighted << 16) | next_sum
}

///|
/// Encode an image from a row provider and emit bounded PNG fragments.
///
/// The callback receives the PNG signature followed by complete IHDR, IDAT,
/// and IEND chunks. Only the current row, previous row, filter candidates, and
/// one IDAT payload are retained. A row-length error can therefore be reported
/// after earlier fragments have already been emitted.
pub fn encode_rows_with_options(
  width : UInt,
  height : UInt,
  format : PixelFormat,
  options : EncodeOptions,
  idat_chunk_size : Int,
  row_at : (Int) -> Bytes,
  emit : (Bytes) -> Unit,
) -> Result[Unit, EncodeError] {
  if idat_chunk_size <= 0 {
    return Err(EncodeInvalidIdatChunkSize(idat_chunk_size))
  }
  if width == 0U || height == 0U {
    return Err(EncodeInvalidDimensions(width, height))
  }
  if width > 0x7fffffffU || height > 0x7fffffffU {
    return Err(EncodeImageTooLarge(width, height))
  }
  let width_int = width.reinterpret_as_int()
  let height_int = height.reinterpret_as_int()
  let channels = encode_pixel_channels(format)
  if width_int > 0x7fffffff / channels {
    return Err(EncodeImageTooLarge(width, height))
  }
  let row_bytes = width_int * channels

  emit(b"\x89PNG\r\n\x1a\n")
  emit(encode_chunk_bytes(b"IHDR", encode_ihdr_payload(width, height, format)))

  let idat_payload : Array[Byte] = []
  let mut adler = 1U
  encode_emit_idat_byte(idat_payload, idat_chunk_size, emit, b'\x78')
  encode_emit_idat_byte(idat_payload, idat_chunk_size, emit, b'\x01')
  let mut previous_row : Bytes? = None
  for row_index = 0; row_index < height_int; row_index = row_index + 1 {
    let row = row_at(row_index)
    if row.length() != row_bytes {
      return Err(EncodeRowLengthMismatch(row_index, row_bytes, row.length()))
    }
    let (filter, filtered) = encode_choose_filter(
      row,
      previous_row,
      channels,
      options.filter_strategy,
    )
    let scanline_length = row_bytes + 1
    let mut scanline_offset = 0
    while scanline_offset < scanline_length {
      let remaining = scanline_length - scanline_offset
      let block_length = if remaining > 65535 { 65535 } else { remaining }
      let is_final = row_index + 1 == height_int &&
        scanline_offset + block_length == scanline_length
      encode_emit_idat_byte(
        idat_payload,
        idat_chunk_size,
        emit,
        if is_final {
          b'\x01'
        } else {
          b'\x00'
        },
      )
      encode_emit_idat_byte(
        idat_payload,
        idat_chunk_size,
        emit,
        block_length.to_byte(),
      )
      encode_emit_idat_byte(
        idat_payload,
        idat_chunk_size,
        emit,
        (block_length >> 8).to_byte(),
      )
      let inverse = block_length ^ 0xffff
      encode_emit_idat_byte(
        idat_payload,
        idat_chunk_size,
        emit,
        inverse.to_byte(),
      )
      encode_emit_idat_byte(
        idat_payload,
        idat_chunk_size,
        emit,
        (inverse >> 8).to_byte(),
      )
      for index = 0; index < block_length; index = index + 1 {
        let position = scanline_offset + index
        let byte = if position == 0 { filter } else { filtered[position - 1] }
        encode_emit_idat_byte(idat_payload, idat_chunk_size, emit, byte)
        adler = encode_update_adler(adler, byte)
      }
      scanline_offset = scanline_offset + block_length
    }
    previous_row = Some(row)
  }
  encode_emit_idat_byte(
    idat_payload,
    idat_chunk_size,
    emit,
    (adler >> 24).to_byte(),
  )
  encode_emit_idat_byte(
    idat_payload,
    idat_chunk_size,
    emit,
    (adler >> 16).to_byte(),
  )
  encode_emit_idat_byte(
    idat_payload,
    idat_chunk_size,
    emit,
    (adler >> 8).to_byte(),
  )
  encode_emit_idat_byte(idat_payload, idat_chunk_size, emit, adler.to_byte())
  if idat_payload.length() > 0 {
    emit(encode_chunk_bytes(b"IDAT", Bytes::from_array(idat_payload)))
  }
  emit(encode_chunk_bytes(b"IEND", b""))
  Ok(())
}

///|
/// Encode rows with adaptive filtering and 64 KiB maximum IDAT payloads.
pub fn encode_rows(
  width : UInt,
  height : UInt,
  format : PixelFormat,
  row_at : (Int) -> Bytes,
  emit : (Bytes) -> Unit,
) -> Result[Unit, EncodeError] {
  encode_rows_with_options(
    width,
    height,
    format,
    default_encode_options(),
    65536,
    row_at,
    emit,
  )
}

///|
/// Encode row-major 8-bit pixels with a maximum IDAT payload size.
///
/// The compressed zlib stream may be split at any byte boundary. All emitted
/// IDAT chunks remain consecutive and individually checksummed.
pub fn encode_with_idat_chunk_size(
  width : UInt,
  height : UInt,
  format : PixelFormat,
  pixels : Bytes,
  options : EncodeOptions,
  idat_chunk_size : Int,
) -> Result[Bytes, EncodeError] {
  if idat_chunk_size <= 0 {
    return Err(EncodeInvalidIdatChunkSize(idat_chunk_size))
  }
  if width == 0U || height == 0U {
    return Err(EncodeInvalidDimensions(width, height))
  }
  if width > 0x7fffffffU || height > 0x7fffffffU {
    return Err(EncodeImageTooLarge(width, height))
  }
  let width_int = width.reinterpret_as_int()
  let height_int = height.reinterpret_as_int()
  let channels = encode_pixel_channels(format)
  if height_int > 0x7fffffff / channels ||
    width_int > 0x7fffffff / channels / height_int {
    return Err(EncodeImageTooLarge(width, height))
  }
  let expected = width_int * height_int * channels
  if pixels.length() != expected {
    return Err(EncodePixelLengthMismatch(expected, pixels.length()))
  }
  if width_int > (0x7fffffff - height_int) / channels / height_int {
    return Err(EncodeImageTooLarge(width, height))
  }
  let raw_length = expected + height_int
  if raw_length > 0x7fffffff - 63 {
    return Err(EncodeImageTooLarge(width, height))
  }
  let block_count = (raw_length + 65534) / 65535
  if block_count > (0x7fffffff - raw_length - 63) / 5 {
    return Err(EncodeImageTooLarge(width, height))
  }

  let raw : Array[Byte] = []
  raw.reserve_capacity(raw_length)
  let row_bytes = width_int * channels
  let mut previous_row : Bytes? = None
  for row = 0; row < height_int; row = row + 1 {
    let row_start = row * row_bytes
    let current_row = encode_copy_range(pixels, row_start, row_bytes)
    let (filter, filtered) = encode_choose_filter(
      current_row,
      previous_row,
      channels,
      options.filter_strategy,
    )
    raw.push(filter)
    for byte in filtered {
      raw.push(byte)
    }
    previous_row = Some(current_row)
  }

  let compressed = encode_stored_zlib(Bytes::from_array(raw))
  let idat_count = (compressed.length() - 1) / idat_chunk_size + 1
  if compressed.length() > 0x7fffffff - 45 ||
    idat_count > (0x7fffffff - 45 - compressed.length()) / 12 {
    return Err(EncodeImageTooLarge(width, height))
  }
  let output : Array[Byte] = []
  encode_append_bytes(output, b"\x89PNG\r\n\x1a\n")
  encode_append_chunk(
    output,
    b"IHDR",
    encode_ihdr_payload(width, height, format),
  )
  let mut compressed_offset = 0
  while compressed_offset < compressed.length() {
    let remaining = compressed.length() - compressed_offset
    let chunk_length = if remaining > idat_chunk_size {
      idat_chunk_size
    } else {
      remaining
    }
    encode_append_chunk(
      output,
      b"IDAT",
      encode_copy_range(compressed, compressed_offset, chunk_length),
    )
    compressed_offset = compressed_offset + chunk_length
  }
  encode_append_chunk(output, b"IEND", b"")
  Ok(Bytes::from_array(output))
}

///|
/// Encode row-major 8-bit pixels with caller-provided options.
pub fn encode_with_options(
  width : UInt,
  height : UInt,
  format : PixelFormat,
  pixels : Bytes,
  options : EncodeOptions,
) -> Result[Bytes, EncodeError] {
  encode_with_idat_chunk_size(
    width, height, format, pixels, options, 0x7fffffff,
  )
}

///|
/// Encode row-major 8-bit grayscale, grayscale-alpha, RGB, or RGBA pixels.
pub fn encode(
  width : UInt,
  height : UInt,
  format : PixelFormat,
  pixels : Bytes,
) -> Result[Bytes, EncodeError] {
  encode_with_options(width, height, format, pixels, default_encode_options())
}

///|
/// Encode row-major RGBA8 pixels with caller-provided options.
pub fn encode_rgba8_with_options(
  width : UInt,
  height : UInt,
  pixels : Bytes,
  options : EncodeOptions,
) -> Result[Bytes, EncodeError] {
  encode_with_options(width, height, PixelRgba8, pixels, options)
}

///|
/// Encode row-major RGBA8 pixels as a deterministic, non-interlaced PNG.
///
/// The default encoder chooses the lowest-cost PNG filter for each row and
/// writes a standards-compliant stored DEFLATE stream. The result can be
/// decoded without a native compression library and is byte-for-byte stable
/// for the same input.
pub fn encode_rgba8(
  width : UInt,
  height : UInt,
  pixels : Bytes,
) -> Result[Bytes, EncodeError] {
  encode(width, height, PixelRgba8, pixels)
}
