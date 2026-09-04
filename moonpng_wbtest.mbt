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
