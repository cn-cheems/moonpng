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
/// Encode row-major RGBA8 pixels as a deterministic, non-interlaced PNG.
///
/// The encoder writes filter type None and a standards-compliant stored
/// DEFLATE stream. The result can be decoded without a native compression
/// library and is byte-for-byte stable for the same input.
pub fn encode_rgba8(
  width : UInt,
  height : UInt,
  pixels : Bytes,
) -> Result[Bytes, EncodeError] {
  if width == 0U || height == 0U {
    return Err(EncodeInvalidDimensions(width, height))
  }
  if width > 0x7fffffffU || height > 0x7fffffffU {
    return Err(EncodeImageTooLarge(width, height))
  }
  let width_int = width.reinterpret_as_int()
  let height_int = height.reinterpret_as_int()
  if height_int > 0x7fffffff / 4 || width_int > 0x7fffffff / 4 / height_int {
    return Err(EncodeImageTooLarge(width, height))
  }
  let expected = width_int * height_int * 4
  if pixels.length() != expected {
    return Err(EncodePixelLengthMismatch(expected, pixels.length()))
  }
  if width_int > (0x7fffffff - height_int) / 4 / height_int {
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
  let row_bytes = width_int * 4
  for row = 0; row < height_int; row = row + 1 {
    raw.push(b'\x00')
    let row_start = row * row_bytes
    for column = 0; column < row_bytes; column = column + 1 {
      raw.push(pixels.unsafe_get(row_start + column))
    }
  }

  let ihdr : Array[Byte] = []
  encode_append_uint32_be(ihdr, width)
  encode_append_uint32_be(ihdr, height)
  ihdr.push(b'\x08')
  ihdr.push(b'\x06')
  ihdr.push(b'\x00')
  ihdr.push(b'\x00')
  ihdr.push(b'\x00')

  let output : Array[Byte] = []
  encode_append_bytes(output, b"\x89PNG\r\n\x1a\n")
  encode_append_chunk(output, b"IHDR", Bytes::from_array(ihdr))
  encode_append_chunk(
    output,
    b"IDAT",
    encode_stored_zlib(Bytes::from_array(raw)),
  )
  encode_append_chunk(output, b"IEND", b"")
  Ok(Bytes::from_array(output))
}
