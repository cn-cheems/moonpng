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
