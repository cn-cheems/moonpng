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

///|
test "price fixed-Huffman literals and LZ77 matches in bits" {
  @test.assert_eq(deflate_fixed_symbol_bit_count(b'A'.to_int()), 8)
  @test.assert_eq(deflate_fixed_symbol_bit_count(b'\xc8'.to_int()), 9)
  @test.assert_eq(deflate_match_bit_cost(3, 1), 12)
  @test.assert_eq(deflate_match_bit_cost(3, 32768), 25)
}

///|
test "reject an LZ77 match that costs more than its literals" {
  let source : Array[Byte] = [b'a', b'b', b'c']
  for index = 3; index < 32768; index = index + 1 {
    source.push(b'\x00')
  }
  source.push(b'a')
  source.push(b'b')
  source.push(b'c')
  let data = Bytes::from_array(source)
  let head = Array::make(32768, -1)
  let previous = Array::make(data.length(), -1)
  deflate_insert(data, 0, head, previous)
  @test.assert_eq(deflate_find_match(data, 32768, head, previous), (0, 0, 0))
}

///|
test "defer a short match when the next position saves more bits" {
  let data = b"abcdefghijklmnopqrstuvwxyz|XabQ|Xabcdefghijklmnopqrstuvwxyz"
  let current = 32
  let head = Array::make(32768, -1)
  let previous = Array::make(data.length(), -1)
  for offset = 0; offset < current; offset = offset + 1 {
    deflate_insert(data, offset, head, previous)
  }
  let (length, distance, savings) = deflate_find_match(
    data, current, head, previous,
  )
  @test.assert_eq((length, distance, savings), (3, 5, 11))
  deflate_insert(data, current, head, previous)
  let (next_length, _, next_savings) = deflate_find_match(
    data,
    current + 1,
    head,
    previous,
  )
  @test.assert_eq(next_length, 26)
  @test.assert_eq(next_savings > savings, true)
  match inflate_zlib(compress_zlib_fixed(data)) {
    Ok(output) => @test.assert_eq(output, data)
    Err(error) => fail(error.message())
  }
}

///|
fn legacy_write_fixed_block_for_test(
  writer : DeflateBitWriter,
  data : Bytes,
  is_final : Bool,
) -> Unit {
  writer.write_bits(if is_final { 1 } else { 0 }, 1)
  writer.write_bits(1, 2)
  let head = Array::make(32768, -1)
  let previous = Array::make(data.length(), -1)
  let mut offset = 0
  while offset < data.length() {
    let (length, distance, savings) = deflate_find_match(
      data, offset, head, previous,
    )
    if savings > 0 {
      deflate_insert(data, offset, head, previous)
      let (_, _, next_savings) = deflate_find_match(
        data,
        offset + 1,
        head,
        previous,
      )
      if next_savings > savings {
        deflate_write_fixed_symbol(writer, data.unsafe_get(offset).to_int())
        offset = offset + 1
      } else {
        deflate_write_length(writer, length)
        deflate_write_distance(writer, distance)
        for index = 1; index < length; index = index + 1 {
          deflate_insert(data, offset + index, head, previous)
        }
        offset = offset + length
      }
    } else {
      deflate_write_fixed_symbol(writer, data.unsafe_get(offset).to_int())
      deflate_insert(data, offset, head, previous)
      offset = offset + 1
    }
  }
  deflate_write_fixed_symbol(writer, 256)
}

///|
fn legacy_fixed_payload_for_test(data : Bytes) -> Bytes {
  let output : Array[Byte] = []
  let writer : DeflateBitWriter = {
    emit_byte: byte => output.push(byte),
    current: 0,
    used: 0,
  }
  legacy_write_fixed_block_for_test(writer, data, true)
  writer.finish()
  Bytes::from_array(output)
}

///|
fn fixed_blocks_payload_for_test(
  blocks : Array[Bytes],
  use_legacy_writer : Bool,
) -> Bytes {
  let output : Array[Byte] = []
  let writer : DeflateBitWriter = {
    emit_byte: byte => output.push(byte),
    current: 0,
    used: 0,
  }
  for index = 0; index < blocks.length(); index = index + 1 {
    let is_final = index + 1 == blocks.length()
    if use_legacy_writer {
      legacy_write_fixed_block_for_test(writer, blocks[index], is_final)
    } else {
      deflate_write_fixed_block(writer, blocks[index], is_final)
    }
  }
  writer.finish()
  Bytes::from_array(output)
}

///|
test "represent LZ77 decisions as reusable tokens" {
  let tokens = deflate_tokenize_lz77(b"abcabcabcabc")
  @test.assert_eq(tokens.length(), 4)
  match tokens[0] {
    Lz77Literal(b'a') => ()
    _ => fail("expected literal a")
  }
  match tokens[1] {
    Lz77Literal(b'b') => ()
    _ => fail("expected literal b")
  }
  match tokens[2] {
    Lz77Literal(b'c') => ()
    _ => fail("expected literal c")
  }
  match tokens[3] {
    Lz77Match(9, 3) => ()
    _ => fail("expected a length 9, distance 3 match")
  }
}

///|
test "tokenized fixed-Huffman output matches the legacy writer byte-for-byte" {
  let repeated = Bytes::from_array(Array::make(4096, b'a'))
  let lazy_input = b"abcdefghijklmnopqrstuvwxyz|XabQ|Xabcdefghijklmnopqrstuvwxyz"
  let noisy_source : Array[Byte] = []
  let mut state = 1729
  for index = 0; index < 4096; index = index + 1 {
    state = (state * 251 + 137) % 65521
    noisy_source.push((state % 256).to_byte())
  }
  let corpus = [
    b"",
    b"A",
    b"all literal bytes",
    b"abcabcabcabcabcabc",
    repeated,
    lazy_input,
    Bytes::from_array(noisy_source),
  ]
  for data in corpus {
    @test.assert_eq(
      deflate_fixed_payload(data),
      legacy_fixed_payload_for_test(data),
    )
  }
  let blocks = [
    b"first scanline first scanline",
    b"second scanline second scanline second scanline",
    Bytes::from_array(noisy_source),
  ]
  @test.assert_eq(
    fixed_blocks_payload_for_test(blocks, false),
    fixed_blocks_payload_for_test(blocks, true),
  )
}
