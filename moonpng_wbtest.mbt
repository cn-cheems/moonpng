///|
test "PNG signature recognition" {
  @test.assert_eq(has_png_signature(b"\x89PNG\r\n\x1a\n"), true)
  @test.assert_eq(has_png_signature(b"\x89PNG\r\n\x1a"), false)
}

///|
test "chunk type letters" {
  @test.assert_eq(is_ascii_letter(b'A'), true)
  @test.assert_eq(is_ascii_letter(b'z'), true)
  @test.assert_eq(is_ascii_letter(b'0'), false)
}

///|
test "valid PNG color formats" {
  @test.assert_eq(color_format_is_valid(b'\x01', b'\x00'), true)
  @test.assert_eq(color_format_is_valid(b'\x08', b'\x06'), true)
  @test.assert_eq(color_format_is_valid(b'\x04', b'\x06'), false)
  @test.assert_eq(color_format_is_valid(b'\x08', b'\x01'), false)
}

///|
test "reverse all five PNG scanline filters" {
  let filtered = b"\x00\x0a\x14\x1e" +
    b"\x01\x0f\x0a\x0a" +
    b"\x02\x05\x05\x05" +
    b"\x03\x0f\x08\x08" +
    b"\x04\x05\x05\x05"
  let expected = [
    b'\x0a', b'\x14', b'\x1e', b'\x0f', b'\x19', b'\x23', b'\x14', b'\x1e', b'\x28',
    b'\x19', b'\x23', b'\x2d', b'\x1e', b'\x28', b'\x32',
  ]
  match unfilter_scanlines(filtered, 3, 1, 5) {
    Ok(value) => @test.assert_eq(value, expected)
    Err(error) => fail(error.message())
  }
}

///|
test "reject invalid PNG scanline filter" {
  match unfilter_scanlines(b"\x05\x00", 1, 1, 1) {
    Err(InvalidFilter(b'\x05', 0)) => ()
    _ => fail("expected InvalidFilter")
  }
}
