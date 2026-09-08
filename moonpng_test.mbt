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
    let options : @moonpng.EncodeOptions = { filter_strategy: strategy, }
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
