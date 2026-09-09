///|
fn valid_structural_png() -> Bytes {
  b"\x89PNG\r\n\x1a\n" +
  b"\x00\x00\x00\x0dIHDR" +
  b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00" +
  b"\x1f\x15\xc4\x89" +
  b"\x00\x00\x00\x00IDAT\x35\xaf\x06\x1e" +
  b"\x00\x00\x00\x00IEND\xae\x42\x60\x82"
}

///|
test "CRC-32 reference vector" {
  @test.assert_eq(@moonpng.crc32(b"123456789"), 0xcbf43926U)
}

///|
test "structural fixture layout" {
  let fixture = valid_structural_png()
  @test.assert_eq(fixture.length(), 57)
  @test.assert_eq(fixture[12], b'I')
  @test.assert_eq(fixture[13], b'H')
  @test.assert_eq(fixture[14], b'D')
  @test.assert_eq(fixture[15], b'R')
}

///|
test "inspect a 1x1 RGBA PNG container" {
  match @moonpng.inspect(valid_structural_png()) {
    Ok(info) => {
      @test.assert_eq(info.width, 1U)
      @test.assert_eq(info.height, 1U)
      @test.assert_eq(info.bit_depth, b'\x08')
      @test.assert_eq(info.color_type, b'\x06')
      @test.assert_eq(info.chunks.length(), 3)
      @test.assert_eq(info.chunks[0].kind, "IHDR")
      @test.assert_eq(info.chunks[1].kind, "IDAT")
      @test.assert_eq(info.chunks[2].kind, "IEND")
      @test.assert_eq(info.chunks[0].is_critical, true)
    }
    Err(error) => fail(error.message())
  }
}

///|
test "reject a bad signature" {
  match @moonpng.inspect(b"not a png file") {
    Err(@moonpng.InvalidSignature) => ()
    _ => fail("expected InvalidSignature")
  }
}

///|
test "reject a CRC mismatch" {
  let bad_crc = b"\x89PNG\r\n\x1a\n" +
    b"\x00\x00\x00\x0dIHDR" +
    b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00" +
    b"\x1f\x15\xc4\x88"
  match @moonpng.inspect(bad_crc) {
    Err(@moonpng.CrcMismatch("IHDR", 8, _, _)) => ()
    _ => fail("expected an IHDR CRC mismatch")
  }
}

///|
test "reject a truncated chunk" {
  let truncated = b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01"
  match @moonpng.inspect(truncated) {
    Err(@moonpng.TruncatedChunk("IHDR", 8, _, _)) => ()
    _ => fail("expected TruncatedChunk")
  }
}

///|
test "enforce caller-provided chunk limit" {
  match
    @moonpng.inspect_with_limits(
      valid_structural_png(),
      max_chunk_size=4,
      max_chunks=8,
    ) {
    Err(@moonpng.ChunkTooLarge("IHDR", 13, 4)) => ()
    _ => fail("expected ChunkTooLarge")
  }
}

///|
test "reject data after IEND" {
  match @moonpng.inspect(valid_structural_png() + b"x") {
    Err(@moonpng.TrailingData(57)) => ()
    _ => fail("expected TrailingData")
  }
}

///|
fn append_uint32_be_for_test(output : Array[Byte], value : UInt) -> Unit {
  output.push((value >> 24).to_byte())
  output.push((value >> 16).to_byte())
  output.push((value >> 8).to_byte())
  output.push(value.to_byte())
}

///|
fn append_bytes_for_test(output : Array[Byte], data : Bytes) -> Unit {
  for byte in data {
    output.push(byte)
  }
}

///|
fn join_fragments_for_test(fragments : Array[Bytes]) -> Bytes {
  let output : Array[Byte] = []
  for fragment in fragments {
    append_bytes_for_test(output, fragment)
  }
  Bytes::from_array(output)
}

///|
fn copy_range_for_test(data : Bytes, start : Int, length : Int) -> Bytes {
  let output : Array[Byte] = []
  output.reserve_capacity(length)
  for index = 0; index < length; index = index + 1 {
    output.push(data[start + index])
  }
  Bytes::from_array(output)
}

///|
fn encode_gray_with_compression_for_test(
  pixels : Bytes,
  strategy : @moonpng.CompressionStrategy,
) -> Bytes raise {
  let options : @moonpng.EncodeOptions = {
    filter_strategy: @moonpng.FilterNone,
    compression_strategy: strategy,
  }
  match
    @moonpng.encode_with_options(
      pixels.length().reinterpret_as_uint(),
      1U,
      @moonpng.PixelGray8,
      pixels,
      options,
    ) {
    Ok(png) => png
    Err(error) => fail(error.message())
  }
}

///|
fn append_chunk_for_test(
  output : Array[Byte],
  kind : Bytes,
  payload : Bytes,
) -> Unit {
  append_uint32_be_for_test(output, payload.length().reinterpret_as_uint())
  append_bytes_for_test(output, kind)
  append_bytes_for_test(output, payload)
  append_uint32_be_for_test(output, @moonpng.crc32(kind + payload))
}

///|
fn ihdr_payload_for_test(
  width : UInt,
  height : UInt,
  bit_depth : Byte,
  color_type : Byte,
  compression_method : Byte,
  filter_method : Byte,
  interlace_method : Byte,
) -> Bytes {
  let payload : Array[Byte] = []
  append_uint32_be_for_test(payload, width)
  append_uint32_be_for_test(payload, height)
  payload.push(bit_depth)
  payload.push(color_type)
  payload.push(compression_method)
  payload.push(filter_method)
  payload.push(interlace_method)
  Bytes::from_array(payload)
}

///|
fn structural_png_with_ihdr_for_test(ihdr : Bytes) -> Bytes {
  let output : Array[Byte] = []
  append_bytes_for_test(output, b"\x89PNG\r\n\x1a\n")
  append_chunk_for_test(output, b"IHDR", ihdr)
  append_chunk_for_test(output, b"IDAT", b"")
  append_chunk_for_test(output, b"IEND", b"")
  Bytes::from_array(output)
}

///|
test "reject every truncated prefix of a valid PNG" {
  let fixture = valid_structural_png()
  for length = 0; length < fixture.length(); length = length + 1 {
    let prefix = copy_range_for_test(fixture, 0, length)
    match @moonpng.inspect(prefix) {
      Err(_) => ()
      Ok(_) => fail("accepted truncated PNG prefix of length \{length}")
    }
  }
}

///|
test "reject every single-bit mutation of a valid PNG" {
  let fixture = valid_structural_png()
  for offset = 0; offset < fixture.length(); offset = offset + 1 {
    for bit = 0; bit < 8; bit = bit + 1 {
      let mutated = fixture.to_array()
      mutated[offset] = mutated[offset] ^ (1 << bit).to_byte()
      match @moonpng.inspect(Bytes::from_array(mutated)) {
        Err(_) => ()
        Ok(_) => fail("accepted one-bit mutation at byte \{offset}, bit \{bit}")
      }
    }
  }
}

///|
test "reject zero PNG dimensions after a valid CRC" {
  let zero_width = structural_png_with_ihdr_for_test(
    ihdr_payload_for_test(0U, 1U, b'\x08', b'\x06', b'\x00', b'\x00', b'\x00'),
  )
  match @moonpng.inspect(zero_width) {
    Err(@moonpng.InvalidDimensions(0U, 1U)) => ()
    _ => fail("expected zero width to be rejected")
  }
  let zero_height = structural_png_with_ihdr_for_test(
    ihdr_payload_for_test(1U, 0U, b'\x08', b'\x06', b'\x00', b'\x00', b'\x00'),
  )
  match @moonpng.inspect(zero_height) {
    Err(@moonpng.InvalidDimensions(1U, 0U)) => ()
    _ => fail("expected zero height to be rejected")
  }
}

///|
test "reject invalid PNG bit-depth and color-type pairs after a valid CRC" {
  let invalid_pairs : Array[(Byte, Byte)] = [
    (b'\x01', b'\x02'),
    (b'\x02', b'\x04'),
    (b'\x04', b'\x06'),
    (b'\x10', b'\x03'),
  ]
  for pair in invalid_pairs {
    let (bit_depth, color_type) = pair
    let png = structural_png_with_ihdr_for_test(
      ihdr_payload_for_test(
        1U, 1U, bit_depth, color_type, b'\x00', b'\x00', b'\x00',
      ),
    )
    match @moonpng.inspect(png) {
      Err(@moonpng.InvalidColorFormat(actual_depth, actual_color)) => {
        @test.assert_eq(actual_depth, bit_depth)
        @test.assert_eq(actual_color, color_type)
      }
      _ =>
        fail(
          "expected invalid depth/color pair \{bit_depth}/\{color_type} to be rejected",
        )
    }
  }
}

///|
test "reject unsupported PNG header methods after a valid CRC" {
  let compression = structural_png_with_ihdr_for_test(
    ihdr_payload_for_test(1U, 1U, b'\x08', b'\x06', b'\x01', b'\x00', b'\x00'),
  )
  match @moonpng.inspect(compression) {
    Err(@moonpng.InvalidCompressionMethod(b'\x01')) => ()
    _ => fail("expected unsupported compression method")
  }
  let filter = structural_png_with_ihdr_for_test(
    ihdr_payload_for_test(1U, 1U, b'\x08', b'\x06', b'\x00', b'\x01', b'\x00'),
  )
  match @moonpng.inspect(filter) {
    Err(@moonpng.InvalidFilterMethod(b'\x01')) => ()
    _ => fail("expected unsupported filter method")
  }
  let interlace = structural_png_with_ihdr_for_test(
    ihdr_payload_for_test(1U, 1U, b'\x08', b'\x06', b'\x00', b'\x00', b'\x02'),
  )
  match @moonpng.inspect(interlace) {
    Err(@moonpng.InvalidInterlaceMethod(b'\x02')) => ()
    _ => fail("expected unsupported interlace method")
  }
}

///|
fn png_with_ancillary_for_test(kind : Bytes, payload : Bytes) -> Bytes {
  let output : Array[Byte] = []
  append_bytes_for_test(output, b"\x89PNG\r\n\x1a\n")
  append_chunk_for_test(
    output, b"IHDR", b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00",
  )
  append_chunk_for_test(output, kind, payload)
  append_chunk_for_test(output, b"IDAT", b"")
  append_chunk_for_test(output, b"IEND", b"")
  Bytes::from_array(output)
}

///|
fn insert_ancillary_before_idat_for_test(
  data : Bytes,
  kind : Bytes,
  payload : Bytes,
) -> Bytes raise {
  let info = match @moonpng.inspect(data) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let output : Array[Byte] = []
  append_bytes_for_test(output, copy_range_for_test(data, 0, 8))
  let mut inserted = false
  for chunk in info.chunks {
    if !inserted && chunk.kind == "IDAT" {
      append_chunk_for_test(output, kind, payload)
      inserted = true
    }
    append_bytes_for_test(
      output,
      copy_range_for_test(data, chunk.offset, chunk.length + 12),
    )
  }
  Bytes::from_array(output)
}

///|
fn chunk_bytes_for_test(data : Bytes, kind : String) -> Bytes raise {
  let info = match @moonpng.inspect(data) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  for chunk in info.chunks {
    if chunk.kind == kind {
      return copy_range_for_test(data, chunk.offset, chunk.length + 12)
    }
  }
  fail("missing chunk: " + kind)
}

///|
fn stored_zlib_for_test(raw : Bytes) -> Bytes {
  let output : Array[Byte] = [b'\x78', b'\x01', b'\x01']
  let length = raw.length()
  let inverse = length ^ 0xffff
  output.push(length.to_byte())
  output.push((length >> 8).to_byte())
  output.push(inverse.to_byte())
  output.push((inverse >> 8).to_byte())
  append_bytes_for_test(output, raw)
  append_uint32_be_for_test(output, @moonpng.adler32(raw))
  Bytes::from_array(output)
}

///|
fn png_custom_with_idat_parts_for_test(
  width : UInt,
  height : UInt,
  bit_depth : Byte,
  color_type : Byte,
  interlace_method : Byte,
  idat_parts : Array[Bytes],
  palette : Bytes?,
  transparency : Bytes?,
) -> Bytes {
  let ihdr : Array[Byte] = []
  append_uint32_be_for_test(ihdr, width)
  append_uint32_be_for_test(ihdr, height)
  ihdr.push(bit_depth)
  ihdr.push(color_type)
  ihdr.push(b'\x00')
  ihdr.push(b'\x00')
  ihdr.push(interlace_method)
  let output : Array[Byte] = []
  append_bytes_for_test(output, b"\x89PNG\r\n\x1a\n")
  append_chunk_for_test(output, b"IHDR", Bytes::from_array(ihdr))
  match palette {
    Some(payload) => append_chunk_for_test(output, b"PLTE", payload)
    None => ()
  }
  match transparency {
    Some(payload) => append_chunk_for_test(output, b"tRNS", payload)
    None => ()
  }
  for part in idat_parts {
    append_chunk_for_test(output, b"IDAT", part)
  }
  append_chunk_for_test(output, b"IEND", b"")
  Bytes::from_array(output)
}

///|
fn png_with_idat_parts_for_test(
  width : UInt,
  height : UInt,
  color_type : Byte,
  idat_parts : Array[Bytes],
  transparency : Bytes?,
) -> Bytes {
  png_custom_with_idat_parts_for_test(
    width,
    height,
    b'\x08',
    color_type,
    b'\x00',
    idat_parts,
    None,
    transparency,
  )
}

///|
fn png_for_test(
  width : UInt,
  height : UInt,
  color_type : Byte,
  scanlines : Bytes,
  transparency : Bytes?,
) -> Bytes {
  png_with_idat_parts_for_test(
    width,
    height,
    color_type,
    [stored_zlib_for_test(scanlines)],
    transparency,
  )
}

///|
fn png_custom_for_test(
  width : UInt,
  height : UInt,
  bit_depth : Byte,
  color_type : Byte,
  scanlines : Bytes,
  palette : Bytes?,
  transparency : Bytes?,
) -> Bytes {
  png_custom_with_idat_parts_for_test(
    width,
    height,
    bit_depth,
    color_type,
    b'\x00',
    [stored_zlib_for_test(scanlines)],
    palette,
    transparency,
  )
}

///|
fn png_interlaced_for_test(
  width : UInt,
  height : UInt,
  bit_depth : Byte,
  color_type : Byte,
  scanlines : Bytes,
  palette : Bytes?,
  transparency : Bytes?,
) -> Bytes {
  png_custom_with_idat_parts_for_test(
    width,
    height,
    bit_depth,
    color_type,
    b'\x01',
    [stored_zlib_for_test(scanlines)],
    palette,
    transparency,
  )
}

///|
test "Adler-32 reference vector" {
  @test.assert_eq(@moonpng.adler32(b"Wikipedia"), 0x11e60398U)
}

///|
test "fixed-Huffman compressor emits deterministic short streams" {
  @test.assert_eq(
    @moonpng.compress_zlib_fixed(b""),
    b"\x78\x01\x03\x00\x00\x00\x00\x01",
  )
  @test.assert_eq(
    @moonpng.compress_zlib_fixed(b"A"),
    b"\x78\x01\x73\x04\x00\x00\x42\x00\x42",
  )
}

///|
test "fixed-Huffman compressor round trips every literal byte" {
  let source : Array[Byte] = []
  for value = 0; value < 256; value = value + 1 {
    source.push(value.to_byte())
  }
  let input = Bytes::from_array(source)
  let compressed = @moonpng.compress_zlib_fixed(input)
  @test.assert_eq(compressed[2].to_int() & 7, 3)
  match @moonpng.inflate_zlib(compressed) {
    Ok(output) => @test.assert_eq(output, input)
    Err(error) => fail(error.message())
  }
}

///|
test "fixed-Huffman compressor uses long LZ77 matches" {
  let source : Array[Byte] = []
  for index = 0; index < 4096; index = index + 1 {
    source.push(
      if index % 3 == 0 {
        b'a'
      } else if index % 3 == 1 {
        b'b'
      } else {
        b'c'
      },
    )
  }
  let input = Bytes::from_array(source)
  let compressed = @moonpng.compress_zlib_fixed(input)
  @test.assert_eq(compressed, @moonpng.compress_zlib_fixed(input))
  @test.assert_eq(compressed.length() < input.length() / 4, true)
  match @moonpng.inflate_zlib(compressed) {
    Ok(output) => @test.assert_eq(output, input)
    Err(error) => fail(error.message())
  }
}

///|
test "fixed-Huffman compressor accepts a 32 KiB match distance" {
  let source : Array[Byte] = [b'a', b'b', b'c']
  for index = 3; index < 32768; index = index + 1 {
    source.push(b'\x00')
  }
  source.push(b'a')
  source.push(b'b')
  source.push(b'c')
  for index = 3; index < 258; index = index + 1 {
    source.push(b'\x00')
  }
  let input = Bytes::from_array(source)
  let compressed = @moonpng.compress_zlib_fixed(input)
  match @moonpng.inflate_zlib(compressed) {
    Ok(output) => @test.assert_eq(output, input)
    Err(error) => fail(error.message())
  }
}

///|
test "standalone zlib strategies select the shortest valid stream" {
  let repeated = Bytes::from_array(Array::make(1024, b'a'))
  let repeated_stored = @moonpng.compress_zlib_stored(repeated)
  let repeated_fixed = @moonpng.compress_zlib_fixed(repeated)
  let repeated_auto = @moonpng.compress_zlib(repeated, @moonpng.CompressionAuto)
  @test.assert_eq(repeated_fixed.length() < repeated_stored.length(), true)
  @test.assert_eq(repeated_auto, repeated_fixed)
  match @moonpng.inflate_zlib(repeated_auto) {
    Ok(output) => @test.assert_eq(output, repeated)
    Err(error) => fail(error.message())
  }

  let noisy_source : Array[Byte] = []
  let mut state = 1729
  for index = 0; index < 1024; index = index + 1 {
    state = (state * 251 + 137) % 65521
    noisy_source.push((state % 256).to_byte())
  }
  let noise = Bytes::from_array(noisy_source)
  let noise_stored = @moonpng.compress_zlib_stored(noise)
  let noise_fixed = @moonpng.compress_zlib_fixed(noise)
  let noise_auto = @moonpng.compress_zlib(noise, @moonpng.CompressionAuto)
  @test.assert_eq(noise_stored.length() < noise_fixed.length(), true)
  @test.assert_eq(noise_auto, noise_stored)
  @test.assert_eq(
    @moonpng.compress_zlib(noise, @moonpng.CompressionStored),
    noise_stored,
  )
  @test.assert_eq(
    @moonpng.compress_zlib(noise, @moonpng.CompressionFixed),
    noise_fixed,
  )
  match @moonpng.inflate_zlib(noise_auto) {
    Ok(output) => @test.assert_eq(output, noise)
    Err(error) => fail(error.message())
  }
}

///|
test "inflate stored DEFLATE block" {
  let stream = b"\x78\x01\x01\x0c\x00\xf3\xffstored block\x1f\x80\x04\xbd"
  match @moonpng.inflate_zlib(stream) {
    Ok(value) => @test.assert_eq(value, b"stored block")
    Err(error) => fail(error.message())
  }
}

///|
test "inflate fixed Huffman DEFLATE block" {
  let stream = b"\x78\xda\x63\xf8\xcf\xc0\xf0\x1f\x00\x05\x00\x01\xff"
  match @moonpng.inflate_zlib(stream) {
    Ok(value) => @test.assert_eq(value, b"\x00\xff\x00\x00\xff")
    Err(error) => fail(error.message())
  }
}

///|
test "inflate dynamic Huffman DEFLATE block" {
  let stream = b"\x78\xda\x2d\x8c\x0b\x0e\x00\x00\x08\x41\x79\xf7\x3f\x74\x58\xeb\x83\x58\x42\x96\x6d\xac\x11\xc4\x56\x84\x44\x60\xcd\x1c\x0f\xa3\xa9\x15\x15\xd6\xa9\xd9\x6a\x60\x39\x7a\xff\x5c\x7e\x1f\x13\x64\x00\x6a"
  let expected = b"\x00\x02\x00\x01\x00\x01\x01\x01\x02\x01\x00\x00\x01\x00\x01\x01\x02\x00\x02\x01\x01\x02\x00\x02\x00\x01\x00\x00\x00\x02\x02\x00\x01\x02\x00\x01\x02\x00\x02\x00\x01\x01\x02\x00\x01\x00\x02\x00\x01\x01\x00\x01\x02\x02\x00\x00\x02\x02\x01\x00\x02\x01\x02\x02\x02\x01\x02\x02\x00\x01\x01\x02\x01\x02\x01\x02\x00\x01\x00\x02\x01\x01\x02\x00\x01\x02\x02\x02\x02\x01\x00\x01\x02\x02\x00\x00\x02\x01\x01\x01"
  match @moonpng.inflate_zlib(stream) {
    Ok(value) => @test.assert_eq(value, expected)
    Err(error) => fail(error.message())
  }
}

///|
test "enforce inflate output limit" {
  let stream = b"\x78\x01\x01\x0c\x00\xf3\xffstored block\x1f\x80\x04\xbd"
  match @moonpng.inflate_zlib_with_limit(stream, max_output_size=4) {
    Err(@moonpng.OutputLimitExceeded(4)) => ()
    _ => fail("expected OutputLimitExceeded")
  }
}

///|
test "reject incorrect zlib checksum" {
  let stream = b"\x78\xda\x63\xf8\xcf\xc0\xf0\x1f\x00\x05\x00\x01\xfe"
  match @moonpng.inflate_zlib(stream) {
    Err(@moonpng.AdlerMismatch(_, _)) => ()
    _ => fail("expected AdlerMismatch")
  }
}

///|
test "reject trailing DEFLATE payload bytes" {
  let stream = b"\x78\xda\x63\xf8\xcf\xc0\xf0\x1f\x00\x00\x05\x00\x01\xff"
  match @moonpng.inflate_zlib(stream) {
    Err(@moonpng.TrailingDeflateData(1)) => ()
    _ => fail("expected TrailingDeflateData")
  }
}

///|
test "decode four common 8-bit PNG color types" {
  let cases : Array[(Byte, Bytes, Bytes, Bytes?)] = [
    (b'\x00', b"\x00\x7f", b"\x7f\x7f\x7f\x00", Some(b"\x00\x7f")),
    (
      b'\x02',
      b"\x00\x01\x02\x03",
      b"\x01\x02\x03\x00",
      Some(b"\x00\x01\x00\x02\x00\x03"),
    ),
    (b'\x04', b"\x00\x44\x55", b"\x44\x44\x44\x55", None),
    (b'\x06', b"\x00\x11\x22\x33\x44", b"\x11\x22\x33\x44", None),
  ]
  for item in cases {
    let (color_type, scanline, expected, transparency) = item
    let png = png_for_test(1U, 1U, color_type, scanline, transparency)
    match @moonpng.decode(png) {
      Ok(image) => {
        @test.assert_eq(image.width, 1U)
        @test.assert_eq(image.height, 1U)
        @test.assert_eq(image.pixels, expected)
        @test.assert_eq(image.pixel_at(0, 0) is Some(_), true)
        @test.assert_eq(image.pixel_at(1, 0), None)
      }
      Err(error) => fail(error.message())
    }
  }
}

///|
test "decode 16-bit PNG color types" {
  let cases : Array[(Byte, Bytes, Bytes, Bytes?)] = [
    (b'\x00', b"\x00\x12\x34", b"\x12\x12\x12\x00", Some(b"\x12\x34")),
    (
      b'\x02',
      b"\x00\x12\x34\x56\x78\x9a\xbc",
      b"\x12\x56\x9a\x00",
      Some(b"\x12\x34\x56\x78\x9a\xbc"),
    ),
    (b'\x04', b"\x00\x44\x55\x66\x77", b"\x44\x44\x44\x66", None),
    (
      b'\x06',
      b"\x00\x11\x22\x33\x44\x55\x66\x77\x88",
      b"\x11\x33\x55\x77",
      None,
    ),
  ]
  for item in cases {
    let (color_type, scanline, expected, transparency) = item
    let png = png_custom_for_test(
      1U,
      1U,
      b'\x10',
      color_type,
      scanline,
      None,
      transparency,
    )
    match @moonpng.decode(png) {
      Ok(image) => @test.assert_eq(image.pixels, expected)
      Err(error) => fail(error.message())
    }
  }

  let low_byte_mismatch = png_custom_for_test(
    1U,
    1U,
    b'\x10',
    b'\x00',
    b"\x00\x12\x34",
    None,
    Some(b"\x12\x35"),
  )
  match @moonpng.decode(low_byte_mismatch) {
    Ok(image) => @test.assert_eq(image.pixels, b"\x12\x12\x12\xff")
    Err(error) => fail(error.message())
  }
}

///|
test "decode filtered RGBA scanlines" {
  let filtered = b"\x01\x0a\x14\x1e\x28\x28\x28\x28\x28" +
    b"\x04\x05\x05\x05\x05\x05\x05\x05\x05"
  let expected = b"\x0a\x14\x1e\x28\x32\x3c\x46\x50" +
    b"\x0f\x19\x23\x2d\x37\x41\x4b\x55"
  match @moonpng.decode(png_for_test(2U, 2U, b'\x06', filtered, None)) {
    Ok(image) => {
      @test.assert_eq(image.pixels, expected)
      @test.assert_eq(
        image.pixel_at(1, 1),
        Some({ red: b'\x37', green: b'\x41', blue: b'\x4b', alpha: b'\x55', }),
      )
    }
    Err(error) => fail(error.message())
  }
}

///|
test "decode dynamically compressed grayscale scanlines" {
  let stream = b"\x78\xda\x2d\x8c\x0b\x0e\x00\x00\x08\x41\x79\xf7\x3f\x74\x58\xeb\x83\x58\x42\x96\x6d\xac\x11\xc4\x56\x84\x44\x60\xcd\x1c\x0f\xa3\xa9\x15\x15\xd6\xa9\xd9\x6a\x60\x39\x7a\xff\x5c\x7e\x1f\x13\x64\x00\x6a"
  let png = png_with_idat_parts_for_test(19U, 5U, b'\x00', [stream], None)
  match @moonpng.decode(png) {
    Ok(image) => {
      @test.assert_eq(image.width, 19U)
      @test.assert_eq(image.height, 5U)
      @test.assert_eq(
        image.pixel_at(0, 0),
        Some({ red: b'\x02', green: b'\x02', blue: b'\x02', alpha: b'\xff', }),
      )
      @test.assert_eq(
        image.pixel_at(10, 3),
        Some({ red: b'\x0b', green: b'\x0b', blue: b'\x0b', alpha: b'\xff', }),
      )
      @test.assert_eq(
        image.pixel_at(18, 4),
        Some({ red: b'\x17', green: b'\x17', blue: b'\x17', alpha: b'\xff', }),
      )
    }
    Err(error) => fail(error.message())
  }
}

///|
test "decode zlib stream split across consecutive IDAT chunks" {
  let png = png_with_idat_parts_for_test(
    1U,
    1U,
    b'\x06',
    [b"\x78\xda\x63\xf8\xcf", b"\xc0\xf0\x1f\x00\x05\x00\x01\xff"],
    None,
  )
  match @moonpng.decode(png) {
    Ok(image) => @test.assert_eq(image.pixels, b"\xff\x00\x00\xff")
    Err(error) => fail(error.message())
  }
}

///|
test "decode packed grayscale samples" {
  let one_bit = png_custom_for_test(
    8U,
    1U,
    b'\x01',
    b'\x00',
    b"\x00\xb2",
    None,
    None,
  )
  match @moonpng.decode(one_bit) {
    Ok(image) => {
      @test.assert_eq(
        image.pixel_at(0, 0),
        Some({ red: b'\xff', green: b'\xff', blue: b'\xff', alpha: b'\xff', }),
      )
      @test.assert_eq(
        image.pixel_at(1, 0),
        Some({ red: b'\x00', green: b'\x00', blue: b'\x00', alpha: b'\xff', }),
      )
      @test.assert_eq(
        image.pixel_at(7, 0),
        Some({ red: b'\x00', green: b'\x00', blue: b'\x00', alpha: b'\xff', }),
      )
    }
    Err(error) => fail(error.message())
  }

  let two_bit = png_custom_for_test(
    4U,
    1U,
    b'\x02',
    b'\x00',
    b"\x00\x1b",
    None,
    Some(b"\x00\x02"),
  )
  match @moonpng.decode(two_bit) {
    Ok(image) =>
      @test.assert_eq(
        image.pixels,
        b"\x00\x00\x00\xff\x55\x55\x55\xff\xaa\xaa\xaa\x00\xff\xff\xff\xff",
      )
    Err(error) => fail(error.message())
  }

  let four_bit = png_custom_for_test(
    3U,
    1U,
    b'\x04',
    b'\x00',
    b"\x00\x08\xf0",
    None,
    None,
  )
  match @moonpng.decode(four_bit) {
    Ok(image) =>
      @test.assert_eq(
        image.pixels,
        b"\x00\x00\x00\xff\x88\x88\x88\xff\xff\xff\xff\xff",
      )
    Err(error) => fail(error.message())
  }
}

///|
test "decode an indexed-color image with palette transparency" {
  let palette = b"\xff\x00\x00\x00\xff\x00\x00\x00\xff\xff\xff\x00"
  let png = png_custom_for_test(
    4U,
    1U,
    b'\x02',
    b'\x03',
    b"\x00\x1b",
    Some(palette),
    Some(b"\xff\x80\x00"),
  )
  match @moonpng.decode(png) {
    Ok(image) =>
      @test.assert_eq(
        image.pixels,
        b"\xff\x00\x00\xff\x00\xff\x00\x80\x00\x00\xff\x00\xff\xff\x00\xff",
      )
    Err(error) => fail(error.message())
  }
}

///|
test "apply byte filters before unpacking samples" {
  let png = png_custom_for_test(
    16U,
    1U,
    b'\x01',
    b'\x00',
    b"\x01\xaa\x55",
    None,
    None,
  )
  match @moonpng.decode(png) {
    Ok(image) => {
      @test.assert_eq(
        image.pixel_at(0, 0),
        Some({ red: b'\xff', green: b'\xff', blue: b'\xff', alpha: b'\xff', }),
      )
      @test.assert_eq(
        image.pixel_at(1, 0),
        Some({ red: b'\x00', green: b'\x00', blue: b'\x00', alpha: b'\xff', }),
      )
      @test.assert_eq(
        image.pixel_at(8, 0),
        Some({ red: b'\xff', green: b'\xff', blue: b'\xff', alpha: b'\xff', }),
      )
      @test.assert_eq(
        image.pixel_at(15, 0),
        Some({ red: b'\xff', green: b'\xff', blue: b'\xff', alpha: b'\xff', }),
      )
    }
    Err(error) => fail(error.message())
  }
}

///|
test "decode Adam7 interlaced RGBA pixels" {
  let passes = b"\x00\x01\x02\x03\xff" +
    b"\x00\x21\x22\x23\xff" +
    b"\x00\x61\x62\x63\xff\x81\x82\x83\xff" +
    b"\x00\x11\x12\x13\xff\x00\x71\x72\x73\xff" +
    b"\x00\x31\x32\x33\xff\x41\x42\x43\xff\x51\x52\x53\xff"
  let png = png_interlaced_for_test(
    3U,
    3U,
    b'\x08',
    b'\x06',
    passes,
    None,
    None,
  )
  let expected = b"\x01\x02\x03\xff\x11\x12\x13\xff\x21\x22\x23\xff" +
    b"\x31\x32\x33\xff\x41\x42\x43\xff\x51\x52\x53\xff" +
    b"\x61\x62\x63\xff\x71\x72\x73\xff\x81\x82\x83\xff"
  match @moonpng.decode(png) {
    Ok(image) => @test.assert_eq(image.pixels, expected)
    Err(error) => fail(error.message())
  }
}

///|
test "decode packed Adam7 indexed pixels" {
  let passes = b"\x00\x00" +
    b"\x00\x80" +
    b"\x00\x80" +
    b"\x00\x40\x00\xc0" +
    b"\x00\xc4"
  let palette = b"\x00\x00\x00\x55\x55\x55\xaa\xaa\xaa\xff\xff\xff"
  let png = png_interlaced_for_test(
    3U,
    3U,
    b'\x02',
    b'\x03',
    passes,
    Some(palette),
    None,
  )
  let expected = b"\x00\x00\x00\xff\x55\x55\x55\xff\xaa\xaa\xaa\xff" +
    b"\xff\xff\xff\xff\x00\x00\x00\xff\x55\x55\x55\xff" +
    b"\xaa\xaa\xaa\xff\xff\xff\xff\xff\x00\x00\x00\xff"
  match @moonpng.decode(png) {
    Ok(image) => @test.assert_eq(image.pixels, expected)
    Err(error) => fail(error.message())
  }
}

///|
test "reject indexed-color metadata errors" {
  let missing = png_custom_for_test(
    1U,
    1U,
    b'\x02',
    b'\x03',
    b"\x00\x00",
    None,
    None,
  )
  match @moonpng.decode(missing) {
    Err(@moonpng.MissingPalette) => ()
    _ => fail("expected MissingPalette")
  }

  let too_large = png_custom_for_test(
    1U,
    1U,
    b'\x01',
    b'\x03',
    b"\x00\x00",
    Some(b"\x00\x00\x00\x11\x11\x11\x22\x22\x22"),
    None,
  )
  match @moonpng.decode(too_large) {
    Err(@moonpng.PaletteTooLarge(3, b'\x01')) => ()
    _ => fail("expected PaletteTooLarge")
  }

  let bad_alpha = png_custom_for_test(
    1U,
    1U,
    b'\x02',
    b'\x03',
    b"\x00\x00",
    Some(b"\xff\x00\x00"),
    Some(b"\xff\x80"),
  )
  match @moonpng.decode(bad_alpha) {
    Err(@moonpng.InvalidTransparency(b'\x03', 2)) => ()
    _ => fail("expected InvalidTransparency")
  }

  let bad_index = png_custom_for_test(
    1U,
    1U,
    b'\x02',
    b'\x03',
    b"\x00\x40",
    Some(b"\xff\x00\x00"),
    None,
  )
  match @moonpng.decode(bad_index) {
    Err(@moonpng.PaletteIndexOutOfRange(1, 0, 0)) => ()
    _ => fail("expected PaletteIndexOutOfRange")
  }
}

///|
test "reject dimensions that overflow the RGBA output buffer" {
  let png = png_for_test(536870912U, 1U, b'\x00', b"\x00", None)
  let limits : @moonpng.DecodeLimits = {
    max_chunk_size: 1024,
    max_chunks: 16,
    max_compressed_size: 1024,
    max_inflated_size: 0x7fffffff,
    max_pixels: 0x7fffffff,
  }
  match @moonpng.decode_with_limits(png, limits) {
    Err(@moonpng.ImageTooLarge(536870912U, 1U, _)) => ()
    _ => fail("expected ImageTooLarge")
  }
}

///|
test "reject non-consecutive IDAT chunks" {
  let output : Array[Byte] = []
  append_bytes_for_test(output, b"\x89PNG\r\n\x1a\n")
  append_chunk_for_test(
    output, b"IHDR", b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00",
  )
  append_chunk_for_test(output, b"IDAT", b"")
  append_chunk_for_test(output, b"tEXt", b"key\x00value")
  append_chunk_for_test(output, b"IDAT", b"")
  append_chunk_for_test(output, b"IEND", b"")
  match @moonpng.inspect(Bytes::from_array(output)) {
    Err(@moonpng.NonConsecutiveIdat(_)) => ()
    _ => fail("expected NonConsecutiveIdat")
  }
}

///|
test "reject unknown critical chunk during decoding" {
  let output : Array[Byte] = []
  append_bytes_for_test(output, b"\x89PNG\r\n\x1a\n")
  append_chunk_for_test(
    output, b"IHDR", b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00",
  )
  append_chunk_for_test(output, b"ABCD", b"")
  append_chunk_for_test(
    output,
    b"IDAT",
    stored_zlib_for_test(b"\x00\x01\x02\x03\x04"),
  )
  append_chunk_for_test(output, b"IEND", b"")
  match @moonpng.decode(Bytes::from_array(output)) {
    Err(@moonpng.UnsupportedCriticalChunk("ABCD")) => ()
    _ => fail("expected UnsupportedCriticalChunk")
  }
}

///|
test "encode and decode deterministic RGBA8 PNG" {
  let pixels = b"\xff\x00\x00\xff\x00\xff\x00\x80"
  let first = @moonpng.encode_rgba8(2U, 1U, pixels)
  let second = @moonpng.encode_rgba8(2U, 1U, pixels)
  match (first, second) {
    (Ok(png), Ok(repeated)) => {
      @test.assert_eq(png, repeated)
      match @moonpng.inspect(png) {
        Ok(info) => {
          @test.assert_eq(info.width, 2U)
          @test.assert_eq(info.height, 1U)
          @test.assert_eq(info.color_type, b'\x06')
          @test.assert_eq(info.chunks.length(), 3)
        }
        Err(error) => fail(error.message())
      }
      match @moonpng.decode(png) {
        Ok(image) => @test.assert_eq(image.pixels, pixels)
        Err(error) => fail(error.message())
      }
    }
    _ => fail("expected two encoded PNGs")
  }
}

///|
test "encode stored zlib data across multiple blocks" {
  let source = Array::make(128 * 128 * 4, b'\x00')
  for index = 0; index < source.length(); index = index + 1 {
    source[index] = (index * 29 + 7).to_byte()
  }
  let pixels = Bytes::from_array(source)
  match @moonpng.encode_rgba8(128U, 128U, pixels) {
    Ok(png) =>
      match @moonpng.decode(png) {
        Ok(image) => @test.assert_eq(image.pixels, pixels)
        Err(error) => fail(error.message())
      }
    Err(error) => fail(error.message())
  }
}

///|
test "round trip every encoder filter strategy" {
  let pixels = b"\x64\x64\x64\x64\x64\x64\x64\x64" +
    b"\x64\x64\x64\x64\x64\x64\x64\x64"
  let strategies = [
    @moonpng.FilterNone,
    @moonpng.FilterSub,
    @moonpng.FilterUp,
    @moonpng.FilterAverage,
    @moonpng.FilterPaeth,
    @moonpng.FilterAdaptive,
  ]
  for strategy in strategies {
    let options : @moonpng.EncodeOptions = {
      filter_strategy: strategy,
      compression_strategy: @moonpng.CompressionStored,
    }
    match @moonpng.encode_rgba8_with_options(2U, 2U, pixels, options) {
      Ok(png) =>
        match @moonpng.decode(png) {
          Ok(image) => @test.assert_eq(image.pixels, pixels)
          Err(error) => fail(error.message())
        }
      Err(error) => fail(error.message())
    }
  }
}

///|
test "select stored, fixed-Huffman, and automatic PNG compression" {
  let repeated = Bytes::from_array(Array::make(1024, b'\x00'))
  let repeated_stored = encode_gray_with_compression_for_test(
    repeated,
    @moonpng.CompressionStored,
  )
  let repeated_fixed = encode_gray_with_compression_for_test(
    repeated,
    @moonpng.CompressionFixed,
  )
  let repeated_auto = encode_gray_with_compression_for_test(
    repeated,
    @moonpng.CompressionAuto,
  )
  @test.assert_eq(repeated_fixed.length() < repeated_stored.length(), true)
  @test.assert_eq(repeated_auto, repeated_fixed)
  match @moonpng.inspect(repeated_fixed) {
    Ok(info) => {
      let idat = info.chunks[1]
      @test.assert_eq(repeated_fixed[idat.data_offset + 2].to_int() & 7, 3)
    }
    Err(error) => fail(error.message())
  }
  match @moonpng.decode(repeated_fixed) {
    Ok(image) => {
      @test.assert_eq(image.width, 1024U)
      @test.assert_eq(image.pixels.length(), 4096)
      @test.assert_eq(image.pixels[0], b'\x00')
      @test.assert_eq(image.pixels[4095], b'\xff')
    }
    Err(error) => fail(error.message())
  }

  let literal_source : Array[Byte] = []
  for value = 144; value < 256; value = value + 1 {
    literal_source.push(value.to_byte())
  }
  let literal_bytes = Bytes::from_array(literal_source)
  let literal_stored = encode_gray_with_compression_for_test(
    literal_bytes,
    @moonpng.CompressionStored,
  )
  let literal_fixed = encode_gray_with_compression_for_test(
    literal_bytes,
    @moonpng.CompressionFixed,
  )
  let literal_auto = encode_gray_with_compression_for_test(
    literal_bytes,
    @moonpng.CompressionAuto,
  )
  @test.assert_eq(literal_stored.length() < literal_fixed.length(), true)
  @test.assert_eq(literal_auto, literal_stored)
}

///|
test "stream fixed-Huffman rows into bounded IDAT chunks" {
  let rows : Array[Bytes] = []
  for row = 0; row < 4; row = row + 1 {
    rows.push(Bytes::from_array(Array::make(256, b'\x00')))
  }
  let fragments : Array[Bytes] = []
  let options : @moonpng.EncodeOptions = {
    filter_strategy: @moonpng.FilterNone,
    compression_strategy: @moonpng.CompressionFixed,
  }
  match
    @moonpng.encode_rows_with_options(
      256U,
      4U,
      @moonpng.PixelGray8,
      options,
      11,
      row => rows[row],
      fragment => fragments.push(fragment),
    ) {
    Ok(_) => {
      let png = join_fragments_for_test(fragments)
      match @moonpng.inspect(png) {
        Ok(info) => {
          let mut idat_count = 0
          for chunk in info.chunks {
            if chunk.kind == "IDAT" {
              idat_count = idat_count + 1
              @test.assert_eq(chunk.length <= 11, true)
            }
          }
          @test.assert_eq(idat_count > 1, true)
          let first_idat = info.chunks[1]
          @test.assert_eq(png[first_idat.data_offset + 2].to_int() & 7, 2)
        }
        Err(error) => fail(error.message())
      }
      match @moonpng.decode(png) {
        Ok(image) => {
          @test.assert_eq(image.width, 256U)
          @test.assert_eq(image.height, 4U)
          @test.assert_eq(image.pixels.length(), 4096)
          @test.assert_eq(image.pixels[0], b'\x00')
          @test.assert_eq(image.pixels[4095], b'\xff')
        }
        Err(error) => fail(error.message())
      }
    }
    Err(error) => fail(error.message())
  }
}

///|
test "stream automatic compression with mixed DEFLATE blocks" {
  let literal_row : Array[Byte] = []
  for value = 144; value < 256; value = value + 1 {
    literal_row.push(value.to_byte())
  }
  let literal_bytes = Bytes::from_array(literal_row)
  let rows : Array[Bytes] = [
    literal_bytes,
    Bytes::from_array(Array::make(112, b'\x00')),
    literal_bytes,
  ]
  let fragments : Array[Bytes] = []
  let options : @moonpng.EncodeOptions = {
    filter_strategy: @moonpng.FilterNone,
    compression_strategy: @moonpng.CompressionAuto,
  }
  match
    @moonpng.encode_rows_with_options(
      112U,
      3U,
      @moonpng.PixelGray8,
      options,
      4096,
      row => rows[row],
      fragment => fragments.push(fragment),
    ) {
    Ok(_) => {
      let png = join_fragments_for_test(fragments)
      match @moonpng.inspect(png) {
        Ok(info) => {
          let idat = info.chunks[1]
          @test.assert_eq(png[idat.data_offset + 2].to_int() & 7, 0)
          @test.assert_eq(png[idat.data_offset + 120].to_int() & 7, 2)
        }
        Err(error) => fail(error.message())
      }
      let expected : Array[Byte] = []
      for value = 144; value < 256; value = value + 1 {
        let byte = value.to_byte()
        expected.push(byte)
        expected.push(byte)
        expected.push(byte)
        expected.push(b'\xff')
      }
      for pixel = 0; pixel < 112; pixel = pixel + 1 {
        expected.push(b'\x00')
        expected.push(b'\x00')
        expected.push(b'\x00')
        expected.push(b'\xff')
      }
      for value = 144; value < 256; value = value + 1 {
        let byte = value.to_byte()
        expected.push(byte)
        expected.push(byte)
        expected.push(byte)
        expected.push(b'\xff')
      }
      match @moonpng.decode(png) {
        Ok(image) => @test.assert_eq(image.pixels, Bytes::from_array(expected))
        Err(error) => fail(error.message())
      }
    }
    Err(error) => fail(error.message())
  }
}

///|
test "reject a row width that leaves no filter byte" {
  match
    @moonpng.encode_rows(0x7fffffffU, 1U, @moonpng.PixelGray8, _ => b"", _ => ()) {
    Err(@moonpng.EncodeImageTooLarge(0x7fffffffU, 1U)) => ()
    _ => fail("expected EncodeImageTooLarge")
  }
}

///|
test "choose deterministic adaptive filters per row" {
  let pixels = b"\x64\x64\x64\x64\x64\x64\x64\x64" +
    b"\x64\x64\x64\x64\x64\x64\x64\x64"
  match @moonpng.encode_rgba8(2U, 2U, pixels) {
    Ok(png) =>
      match @moonpng.inspect(png) {
        Ok(info) => {
          let idat = info.chunks[1]
          let raw_offset = idat.data_offset + 7
          @test.assert_eq(png[raw_offset], b'\x01')
          @test.assert_eq(png[raw_offset + 9], b'\x02')
        }
        Err(error) => fail(error.message())
      }
    Err(error) => fail(error.message())
  }
}

///|
test "encode compact 8-bit PNG color formats" {
  let cases : Array[(@moonpng.PixelFormat, Byte, Bytes, Bytes)] = [
    (@moonpng.PixelGray8, b'\x00', b"\x7f", b"\x7f\x7f\x7f\xff"),
    (@moonpng.PixelGrayAlpha8, b'\x04', b"\x44\x55", b"\x44\x44\x44\x55"),
    (@moonpng.PixelRgb8, b'\x02', b"\x11\x22\x33", b"\x11\x22\x33\xff"),
    (@moonpng.PixelRgba8, b'\x06', b"\x11\x22\x33\x44", b"\x11\x22\x33\x44"),
  ]
  for item in cases {
    let (format, color_type, input, expected) = item
    match @moonpng.encode(1U, 1U, format, input) {
      Ok(png) => {
        match @moonpng.inspect(png) {
          Ok(info) => @test.assert_eq(info.color_type, color_type)
          Err(error) => fail(error.message())
        }
        match @moonpng.decode(png) {
          Ok(image) => @test.assert_eq(image.pixels, expected)
          Err(error) => fail(error.message())
        }
      }
      Err(error) => fail(error.message())
    }
  }
}

///|
test "encode a zlib stream across consecutive IDAT chunks" {
  let source = Array::make(32 * 4, b'\x00')
  for index = 0; index < source.length(); index = index + 1 {
    source[index] = (index * 17 + 3).to_byte()
  }
  let pixels = Bytes::from_array(source)
  let options = @moonpng.default_encode_options()
  match
    @moonpng.encode_with_idat_chunk_size(
      32U,
      1U,
      @moonpng.PixelRgba8,
      pixels,
      options,
      11,
    ) {
    Ok(png) => {
      match @moonpng.inspect(png) {
        Ok(info) => {
          let mut idat_count = 0
          for chunk in info.chunks {
            if chunk.kind == "IDAT" {
              idat_count = idat_count + 1
              @test.assert_eq(chunk.length <= 11, true)
            }
          }
          @test.assert_eq(idat_count > 1, true)
        }
        Err(error) => fail(error.message())
      }
      match @moonpng.decode(png) {
        Ok(image) => @test.assert_eq(image.pixels, pixels)
        Err(error) => fail(error.message())
      }
    }
    Err(error) => fail(error.message())
  }
}

///|
test "encode rows into bounded PNG fragments" {
  let rows : Array[Bytes] = [
    b"\xff\x00\x00\x00\xff\x00\x00\x00\xff", b"\xff\xff\xff\x00\x00\x00\x80\x40\x20",
  ]
  let fragments : Array[Bytes] = []
  match
    @moonpng.encode_rows_with_options(
      3U,
      2U,
      @moonpng.PixelRgb8,
      @moonpng.default_encode_options(),
      7,
      row => rows[row],
      fragment => fragments.push(fragment),
    ) {
    Ok(_) => {
      @test.assert_eq(fragments[0], b"\x89PNG\r\n\x1a\n")
      @test.assert_eq(fragments.length() > 4, true)
      let output : Array[Byte] = []
      for fragment in fragments {
        append_bytes_for_test(output, fragment)
      }
      let png = Bytes::from_array(output)
      match @moonpng.inspect(png) {
        Ok(info) => {
          let mut idat_count = 0
          for chunk in info.chunks {
            if chunk.kind == "IDAT" {
              idat_count = idat_count + 1
              @test.assert_eq(chunk.length <= 7, true)
            }
          }
          @test.assert_eq(idat_count > 1, true)
        }
        Err(error) => fail(error.message())
      }
      let expected = b"\xff\x00\x00\xff\x00\xff\x00\xff" +
        b"\x00\x00\xff\xff\xff\xff\xff\xff" +
        b"\x00\x00\x00\xff\x80\x40\x20\xff"
      match @moonpng.decode(png) {
        Ok(image) => @test.assert_eq(image.pixels, expected)
        Err(error) => fail(error.message())
      }
    }
    Err(error) => fail(error.message())
  }
}

///|
test "encode a wide row across stored blocks" {
  let source = Array::make(21846 * 3, b'\x00')
  for index = 0; index < source.length(); index = index + 1 {
    source[index] = (index * 13 + 5).to_byte()
  }
  let pixels = Bytes::from_array(source)
  let fragments : Array[Bytes] = []
  let options : @moonpng.EncodeOptions = {
    filter_strategy: @moonpng.FilterNone,
    compression_strategy: @moonpng.CompressionStored,
  }
  match
    @moonpng.encode_rows_with_options(
      21846U,
      1U,
      @moonpng.PixelRgb8,
      options,
      4096,
      _ => pixels,
      fragment => fragments.push(fragment),
    ) {
    Ok(_) => {
      let output : Array[Byte] = []
      for fragment in fragments {
        append_bytes_for_test(output, fragment)
      }
      match @moonpng.decode(Bytes::from_array(output)) {
        Ok(image) => {
          @test.assert_eq(image.width, 21846U)
          @test.assert_eq(image.pixels.length(), 21846 * 4)
          @test.assert_eq(image.pixels[0], pixels[0])
          @test.assert_eq(image.pixels[21845 * 4 + 2], pixels[21845 * 3 + 2])
        }
        Err(error) => fail(error.message())
      }
    }
    Err(error) => fail(error.message())
  }
}

///|
test "reject an invalid row from the encoder provider" {
  let fragments : Array[Bytes] = []
  match
    @moonpng.encode_rows(2U, 1U, @moonpng.PixelGray8, _ => b"\x01", fragment => {
      fragments.push(fragment)
    }) {
    Err(@moonpng.EncodeRowLengthMismatch(0, 2, 1)) =>
      @test.assert_eq(fragments.length(), 2)
    _ => fail("expected EncodeRowLengthMismatch")
  }
}

///|
test "reject invalid RGBA8 encode input" {
  match @moonpng.encode_rgba8(0U, 1U, b"") {
    Err(@moonpng.EncodeInvalidDimensions(0U, 1U)) => ()
    _ => fail("expected EncodeInvalidDimensions")
  }
  match @moonpng.encode_rgba8(1U, 1U, b"\x00\x01\x02") {
    Err(@moonpng.EncodePixelLengthMismatch(4, 3)) => ()
    _ => fail("expected EncodePixelLengthMismatch")
  }
  match
    @moonpng.encode_with_idat_chunk_size(
      1U,
      1U,
      @moonpng.PixelRgba8,
      b"\x00\x00\x00\xff",
      @moonpng.default_encode_options(),
      0,
    ) {
    Err(@moonpng.EncodeInvalidIdatChunkSize(0)) => ()
    _ => fail("expected EncodeInvalidIdatChunkSize")
  }
}

///|
test "round trip every PNG text format" {
  let entries : Array[@moonpng.TextEntry] = [
    @moonpng.latin1_text("Author", "René"),
    @moonpng.latin1_text("Description", "MoonPNG metadata", compressed=true),
    @moonpng.international_text(
      "Title",
      "月亮图片",
      language_tag="zh-Hans",
      translated_keyword="标题",
    ),
    @moonpng.international_text(
      "Comment",
      "こんにちは PNG",
      language_tag="ja",
      translated_keyword="コメント",
      compressed=true,
    ),
    @moonpng.latin1_text("Disclaimer", "", compressed=true),
  ]
  match @moonpng.replace_text_entries(valid_structural_png(), entries) {
    Err(error) => fail(error.message())
    Ok(png) => {
      match @moonpng.inspect(png) {
        Err(error) => fail(error.message())
        Ok(info) => {
          @test.assert_eq(info.chunks.length(), 8)
          @test.assert_eq(info.chunks[1].kind, "tEXt")
          @test.assert_eq(info.chunks[2].kind, "zTXt")
          @test.assert_eq(info.chunks[3].kind, "iTXt")
          @test.assert_eq(info.chunks[4].kind, "iTXt")
          @test.assert_eq(info.chunks[5].kind, "zTXt")
          @test.assert_eq(info.chunks[6].kind, "IDAT")
        }
      }
      match @moonpng.read_text_entries(png) {
        Err(error) => fail(error.message())
        Ok(decoded) => @test.assert_eq(decoded, entries)
      }
    }
  }
}

///|
test "compress repetitive Latin-1 and international text metadata" {
  let latin = "MoonPNG metadata ".repeat(256)
  let international = "月亮图片".repeat(256)
  let plain_entries = [
    @moonpng.latin1_text("Description", latin),
    @moonpng.international_text(
      "Comment",
      international,
      language_tag="zh-Hans",
      translated_keyword="说明",
    ),
  ]
  let compressed_entries = [
    @moonpng.latin1_text("Description", latin, compressed=true),
    @moonpng.international_text(
      "Comment",
      international,
      language_tag="zh-Hans",
      translated_keyword="说明",
      compressed=true,
    ),
  ]
  let plain = match
    @moonpng.replace_text_entries(valid_structural_png(), plain_entries) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let compressed = match
    @moonpng.replace_text_entries(valid_structural_png(), compressed_entries) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let repeated = match
    @moonpng.replace_text_entries(valid_structural_png(), compressed_entries) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  @test.assert_eq(compressed, repeated)
  @test.assert_eq(compressed.length() * 4 < plain.length(), true)
  match @moonpng.inspect(compressed) {
    Ok(info) => {
      @test.assert_eq(info.chunks[1].kind, "zTXt")
      @test.assert_eq(info.chunks[2].kind, "iTXt")
    }
    Err(error) => fail(error.message())
  }
  match @moonpng.read_text_entries(compressed) {
    Ok(entries) => @test.assert_eq(entries, compressed_entries)
    Err(error) => fail(error.message())
  }
}

///|
test "add and replace text without changing decoded pixels" {
  let pixels = b"\x11\x22\x33\x44\x55\x66\x77\x88"
  let source = match @moonpng.encode_rgba8(2U, 1U, pixels) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let with_author = match
    @moonpng.add_text_entries(source, [
      @moonpng.latin1_text("Author", "cn-cheems"),
    ]) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let with_both = match
    @moonpng.add_text_entries(with_author, [
      @moonpng.international_text("Title", "MoonPNG 示例"),
    ]) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  match @moonpng.read_text_entries(with_both) {
    Ok(entries) => {
      @test.assert_eq(entries.length(), 2)
      @test.assert_eq(entries[0].keyword, "Author")
      @test.assert_eq(entries[1].text, "MoonPNG 示例")
    }
    Err(error) => fail(error.message())
  }
  let replaced = match
    @moonpng.replace_text_entries(with_both, [
      @moonpng.latin1_text("Software", "MoonPNG"),
    ]) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  match @moonpng.read_text_entries(replaced) {
    Ok(entries) => {
      @test.assert_eq(entries.length(), 1)
      @test.assert_eq(entries[0].keyword, "Software")
    }
    Err(error) => fail(error.message())
  }
  match @moonpng.decode(replaced) {
    Ok(image) => @test.assert_eq(image.pixels, pixels)
    Err(error) => fail(error.message())
  }
}

///|
test "replace text preserves every non-text chunk byte-for-byte" {
  let pixels = b"\x10\x20\x30\xff\x40\x50\x60\x80"
  let encoded = match @moonpng.encode_rgba8(2U, 1U, pixels) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let with_dimensions = insert_ancillary_before_idat_for_test(
    encoded, b"pHYs", b"\x00\x00\x0b\x13\x00\x00\x0b\x13\x01",
  )
  let source = insert_ancillary_before_idat_for_test(
    with_dimensions, b"vpAg", b"private payload",
  )
  let source = match
    @moonpng.add_text_entries(source, [
      @moonpng.latin1_text("Author", "cn-cheems"),
    ]) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let header_chunk = chunk_bytes_for_test(source, "IHDR")
  let physical_chunk = chunk_bytes_for_test(source, "pHYs")
  let private_chunk = chunk_bytes_for_test(source, "vpAg")
  let image_chunk = chunk_bytes_for_test(source, "IDAT")
  let end_chunk = chunk_bytes_for_test(source, "IEND")
  let updated = match
    @moonpng.replace_text_entries(source, [
      @moonpng.international_text(
        "Title",
        "MoonPNG 无损元数据编辑",
        language_tag="zh-Hans",
        translated_keyword="标题",
        compressed=true,
      ),
    ]) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  @test.assert_eq(
    copy_range_for_test(updated, 0, 8),
    copy_range_for_test(source, 0, 8),
  )
  @test.assert_eq(chunk_bytes_for_test(updated, "IHDR"), header_chunk)
  @test.assert_eq(chunk_bytes_for_test(updated, "pHYs"), physical_chunk)
  @test.assert_eq(chunk_bytes_for_test(updated, "vpAg"), private_chunk)
  @test.assert_eq(chunk_bytes_for_test(updated, "IDAT"), image_chunk)
  @test.assert_eq(chunk_bytes_for_test(updated, "IEND"), end_chunk)
  match @moonpng.decode(updated) {
    Ok(image) => @test.assert_eq(image.pixels, pixels)
    Err(error) => fail(error.message())
  }
}

///|
test "reject invalid text entries before writing" {
  match
    @moonpng.add_text_entries(valid_structural_png(), [
      @moonpng.latin1_text(" bad", "value"),
    ]) {
    Err(@moonpng.TextInvalidKeyword(0)) => ()
    _ => fail("expected TextInvalidKeyword")
  }
  match
    @moonpng.add_text_entries(valid_structural_png(), [
      @moonpng.latin1_text("Title", "中文"),
    ]) {
    Err(@moonpng.TextInvalidLatin1("text")) => ()
    _ => fail("expected TextInvalidLatin1")
  }
  let invalid_fields : @moonpng.TextEntry = {
    format: @moonpng.TextLatin1,
    keyword: "Title",
    text: "value",
    language_tag: "en",
    translated_keyword: "Title",
  }
  match @moonpng.add_text_entries(valid_structural_png(), [invalid_fields]) {
    Err(@moonpng.TextUnexpectedInternationalFields(0)) => ()
    _ => fail("expected TextUnexpectedInternationalFields")
  }
}

///|
test "reject malformed compressed and international text chunks" {
  let unsupported = png_with_ancillary_for_test(
    b"zTXt", b"Comment\x00\x01compressed",
  )
  match @moonpng.read_text_entries(unsupported) {
    Err(@moonpng.TextUnsupportedCompression("zTXt", b'\x01', _)) => ()
    _ => fail("expected TextUnsupportedCompression")
  }
  let invalid_flag = png_with_ancillary_for_test(
    b"iTXt", b"Comment\x00\x02\x00\x00\x00text",
  )
  match @moonpng.read_text_entries(invalid_flag) {
    Err(@moonpng.TextInvalidCompressionFlag(b'\x02', _)) => ()
    _ => fail("expected TextInvalidCompressionFlag")
  }
  let invalid_utf8 = png_with_ancillary_for_test(
    b"iTXt", b"Title\x00\x00\x00\x00\x00\xff",
  )
  match @moonpng.read_text_entries(invalid_utf8) {
    Err(@moonpng.TextInvalidUtf8("international text")) => ()
    _ => fail("expected TextInvalidUtf8")
  }
  let invalid_language = png_with_ancillary_for_test(
    b"iTXt", b"Title\x00\x00\x00zh_CN\x00\x00text",
  )
  match @moonpng.read_text_entries(invalid_language) {
    Err(@moonpng.TextInvalidLanguageTag(_)) => ()
    _ => fail("expected TextInvalidLanguageTag")
  }
}

///|
test "bound decompressed PNG text" {
  let source = match
    @moonpng.add_text_entries(valid_structural_png(), [
      @moonpng.latin1_text("Description", "A".repeat(128), compressed=true),
    ]) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let limits : @moonpng.TextLimits = {
    max_entries: 4,
    max_encoded_bytes: 4096,
    max_decoded_bytes: 32,
  }
  match @moonpng.read_text_entries_with_limits(source, limits) {
    Err(@moonpng.TextDecodedDataTooLarge(32)) => ()
    _ => fail("expected TextDecodedDataTooLarge")
  }
}
