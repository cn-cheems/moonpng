///|
priv struct BitReader {
  data : Bytes
  end : Int
  mut byte_offset : Int
  mut bit_offset : Int
}

///|
fn BitReader::read_bits(
  self : BitReader,
  count : Int,
) -> Result[Int, DecodeError] {
  let mut value = 0
  for shift = 0; shift < count; shift = shift + 1 {
    if self.byte_offset >= self.end {
      return Err(TruncatedDeflate)
    }
    let current = self.data.unsafe_get(self.byte_offset).to_int()
    value = value | (((current >> self.bit_offset) & 1) << shift)
    self.bit_offset = self.bit_offset + 1
    if self.bit_offset == 8 {
      self.bit_offset = 0
      self.byte_offset = self.byte_offset + 1
    }
  }
  Ok(value)
}

///|
fn BitReader::align_to_byte(self : BitReader) -> Unit {
  if self.bit_offset != 0 {
    self.bit_offset = 0
    self.byte_offset = self.byte_offset + 1
  }
}

///|
priv struct Huffman {
  left : Array[Int]
  right : Array[Int]
  symbols : Array[Int]
  max_bits : Int
}

///|
fn reverse_low_bits(value : Int, count : Int) -> Int {
  let mut input = value
  let mut result = 0
  for index = 0; index < count; index = index + 1 {
    result = (result << 1) | (input & 1)
    input = input >> 1
  }
  result
}

///|
fn build_huffman(lengths : Array[Int]) -> Result[Huffman, DecodeError] {
  let mut max_bits = 0
  for length in lengths {
    if length < 0 || length > 15 {
      return Err(InvalidHuffmanTree)
    }
    if length > max_bits {
      max_bits = length
    }
  }
  if max_bits == 0 {
    return Err(InvalidHuffmanTree)
  }

  let counts = Array::make(max_bits + 1, 0)
  for length in lengths {
    if length != 0 {
      counts[length] = counts[length] + 1
    }
  }

  let mut remaining = 1
  for bits = 1; bits <= max_bits; bits = bits + 1 {
    remaining = (remaining << 1) - counts[bits]
    if remaining < 0 {
      return Err(InvalidHuffmanTree)
    }
  }

  let next_codes = Array::make(max_bits + 1, 0)
  let mut code = 0
  for bits = 1; bits <= max_bits; bits = bits + 1 {
    code = (code + counts[bits - 1]) << 1
    next_codes[bits] = code
  }

  let left : Array[Int] = [-1]
  let right : Array[Int] = [-1]
  let symbols : Array[Int] = [-1]
  for symbol = 0; symbol < lengths.length(); symbol = symbol + 1 {
    let length = lengths[symbol]
    if length != 0 {
      let canonical = next_codes[length]
      next_codes[length] = canonical + 1
      let reversed = reverse_low_bits(canonical, length)
      let mut node = 0
      for depth = 0; depth < length; depth = depth + 1 {
        if symbols[node] >= 0 {
          return Err(InvalidHuffmanTree)
        }
        let bit = (reversed >> depth) & 1
        let mut child = if bit == 0 { left[node] } else { right[node] }
        if child < 0 {
          child = symbols.length()
          left.push(-1)
          right.push(-1)
          symbols.push(-1)
          if bit == 0 {
            left[node] = child
          } else {
            right[node] = child
          }
        }
        node = child
      }
      if symbols[node] >= 0 || left[node] >= 0 || right[node] >= 0 {
        return Err(InvalidHuffmanTree)
      }
      symbols[node] = symbol
    }
  }
  Ok({ left, right, symbols, max_bits, })
}

///|
fn Huffman::decode(
  self : Huffman,
  reader : BitReader,
) -> Result[Int, DecodeError] {
  let mut node = 0
  for depth = 0; depth < self.max_bits; depth = depth + 1 {
    let bit = match reader.read_bits(1) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    node = if bit == 0 { self.left[node] } else { self.right[node] }
    if node < 0 {
      return Err(InvalidHuffmanCode)
    }
    if self.symbols[node] >= 0 {
      return Ok(self.symbols[node])
    }
  }
  Err(InvalidHuffmanCode)
}

///|
let length_bases : Array[Int] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83,
  99, 115, 131, 163, 195, 227, 258,
]

///|
let length_extra_bits : Array[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5,
  5, 0,
]

///|
let distance_bases : Array[Int] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
]

///|
let distance_extra_bits : Array[Int] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
  12, 12, 13, 13,
]

///|
fn fixed_literal_tree() -> Result[Huffman, DecodeError] {
  let lengths = Array::make(288, 0)
  for symbol = 0; symbol <= 143; symbol = symbol + 1 {
    lengths[symbol] = 8
  }
  for symbol = 144; symbol <= 255; symbol = symbol + 1 {
    lengths[symbol] = 9
  }
  for symbol = 256; symbol <= 279; symbol = symbol + 1 {
    lengths[symbol] = 7
  }
  for symbol = 280; symbol <= 287; symbol = symbol + 1 {
    lengths[symbol] = 8
  }
  build_huffman(lengths)
}

///|
fn fixed_distance_tree() -> Result[Huffman, DecodeError] {
  build_huffman(Array::make(32, 5))
}

///|
fn read_dynamic_trees(
  reader : BitReader,
) -> Result[(Huffman, Huffman?), DecodeError] {
  let literal_count = match reader.read_bits(5) {
    Ok(value) => value + 257
    Err(error) => return Err(error)
  }
  let distance_count = match reader.read_bits(5) {
    Ok(value) => value + 1
    Err(error) => return Err(error)
  }
  let code_length_count = match reader.read_bits(4) {
    Ok(value) => value + 4
    Err(error) => return Err(error)
  }
  let order : Array[Int] = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
  ]
  let code_lengths = Array::make(19, 0)
  for index = 0; index < code_length_count; index = index + 1 {
    code_lengths[order[index]] = match reader.read_bits(3) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  let code_tree = match build_huffman(code_lengths) {
    Ok(tree) => tree
    Err(error) => return Err(error)
  }

  let total = literal_count + distance_count
  let lengths : Array[Int] = []
  while lengths.length() < total {
    let symbol = match code_tree.decode(reader) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if symbol <= 15 {
      lengths.push(symbol)
    } else if symbol == 16 {
      if lengths.is_empty() {
        return Err(InvalidCodeLengthRepeat)
      }
      let repeat = match reader.read_bits(2) {
        Ok(value) => value + 3
        Err(error) => return Err(error)
      }
      if repeat > total - lengths.length() {
        return Err(InvalidCodeLengthRepeat)
      }
      let previous = lengths[lengths.length() - 1]
      for index = 0; index < repeat; index = index + 1 {
        lengths.push(previous)
      }
    } else if symbol == 17 {
      let repeat = match reader.read_bits(3) {
        Ok(value) => value + 3
        Err(error) => return Err(error)
      }
      if repeat > total - lengths.length() {
        return Err(InvalidCodeLengthRepeat)
      }
      for index = 0; index < repeat; index = index + 1 {
        lengths.push(0)
      }
    } else if symbol == 18 {
      let repeat = match reader.read_bits(7) {
        Ok(value) => value + 11
        Err(error) => return Err(error)
      }
      if repeat > total - lengths.length() {
        return Err(InvalidCodeLengthRepeat)
      }
      for index = 0; index < repeat; index = index + 1 {
        lengths.push(0)
      }
    } else {
      return Err(InvalidCodeLengthRepeat)
    }
  }

  let literal_lengths = Array::make(literal_count, 0)
  for index = 0; index < literal_count; index = index + 1 {
    literal_lengths[index] = lengths[index]
  }
  if literal_lengths[256] == 0 {
    return Err(InvalidHuffmanTree)
  }
  let literal_tree = match build_huffman(literal_lengths) {
    Ok(tree) => tree
    Err(error) => return Err(error)
  }

  let distance_lengths = Array::make(distance_count, 0)
  let mut has_distance_code = false
  for index = 0; index < distance_count; index = index + 1 {
    let length = lengths[literal_count + index]
    distance_lengths[index] = length
    if length != 0 {
      has_distance_code = true
    }
  }
  let distance_tree = if has_distance_code {
    match build_huffman(distance_lengths) {
      Ok(tree) => Some(tree)
      Err(error) => return Err(error)
    }
  } else {
    None
  }
  Ok((literal_tree, distance_tree))
}

///|
fn append_with_limit(
  output : Array[Byte],
  value : Byte,
  limit : Int,
) -> Result[Unit, DecodeError] {
  if output.length() >= limit {
    return Err(OutputLimitExceeded(limit))
  }
  output.push(value)
  Ok(())
}

///|
fn decode_compressed_block(
  reader : BitReader,
  output : Array[Byte],
  literal_tree : Huffman,
  distance_tree : Huffman?,
  output_limit : Int,
) -> Result[Unit, DecodeError] {
  while true {
    let symbol = match literal_tree.decode(reader) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if symbol < 256 {
      match append_with_limit(output, symbol.to_byte(), output_limit) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    } else if symbol == 256 {
      return Ok(())
    } else {
      if symbol < 257 || symbol > 285 {
        return Err(InvalidLengthSymbol(symbol))
      }
      let length_index = symbol - 257
      let extra_length = match
        reader.read_bits(length_extra_bits[length_index]) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let match_length = length_bases[length_index] + extra_length
      let tree = match distance_tree {
        Some(value) => value
        None => return Err(InvalidHuffmanTree)
      }
      let distance_symbol = match tree.decode(reader) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if distance_symbol < 0 || distance_symbol >= distance_bases.length() {
        return Err(InvalidDistanceSymbol(distance_symbol))
      }
      let extra_distance = match
        reader.read_bits(distance_extra_bits[distance_symbol]) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let distance = distance_bases[distance_symbol] + extra_distance
      if distance <= 0 || distance > output.length() {
        return Err(InvalidBackReference(distance, output.length()))
      }
      if match_length > output_limit - output.length() {
        return Err(OutputLimitExceeded(output_limit))
      }
      for index = 0; index < match_length; index = index + 1 {
        output.push(output[output.length() - distance])
      }
    }
  }
  Ok(())
}

///|
fn decode_stored_block(
  reader : BitReader,
  output : Array[Byte],
  output_limit : Int,
) -> Result[Unit, DecodeError] {
  reader.align_to_byte()
  if reader.end - reader.byte_offset < 4 {
    return Err(TruncatedDeflate)
  }
  let length = reader.data.unsafe_get(reader.byte_offset).to_int() |
    (reader.data.unsafe_get(reader.byte_offset + 1).to_int() << 8)
  let inverse = reader.data.unsafe_get(reader.byte_offset + 2).to_int() |
    (reader.data.unsafe_get(reader.byte_offset + 3).to_int() << 8)
  reader.byte_offset = reader.byte_offset + 4
  if (length ^ 0xffff) != inverse {
    return Err(InvalidStoredBlockLength)
  }
  if length > reader.end - reader.byte_offset {
    return Err(TruncatedDeflate)
  }
  if length > output_limit - output.length() {
    return Err(OutputLimitExceeded(output_limit))
  }
  for index = 0; index < length; index = index + 1 {
    output.push(reader.data.unsafe_get(reader.byte_offset + index))
  }
  reader.byte_offset = reader.byte_offset + length
  Ok(())
}

///|
fn read_uint32_be(data : Bytes, offset : Int) -> UInt {
  data.unsafe_read_uint32_be(offset)
}

///|
fn adler32_range(data : Bytes, start : Int, length : Int) -> UInt {
  let modulus = 65521U
  let mut first = 1U
  let mut second = 0U
  for index = start; index < start + length; index = index + 1 {
    first = (first + data.unsafe_get(index).to_uint()) % modulus
    second = (second + first) % modulus
  }
  (second << 16) | first
}

///|
/// Compute the Adler-32 checksum used by zlib streams.
pub fn adler32(data : Bytes) -> UInt {
  adler32_range(data, 0, data.length())
}

///|
/// Inflate an RFC 1950 zlib stream with a conservative output limit.
pub fn inflate_zlib(data : Bytes) -> Result[Bytes, DecodeError] {
  inflate_zlib_with_limit(data, max_output_size=256 * 1024 * 1024)
}

///|
/// Inflate an RFC 1950 zlib stream while bounding decompressed output.
pub fn inflate_zlib_with_limit(
  data : Bytes,
  max_output_size~ : Int,
) -> Result[Bytes, DecodeError] {
  if max_output_size <= 0 {
    return Err(InvalidDecodeLimits)
  }
  if data.length() < 6 {
    return Err(InvalidZlibHeader)
  }
  let cmf = data.unsafe_get(0).to_int()
  let flg = data.unsafe_get(1).to_int()
  if (cmf & 0x0f) != 8 || cmf >> 4 > 7 || ((cmf << 8) + flg) % 31 != 0 {
    return Err(InvalidZlibHeader)
  }
  if (flg & 0x20) != 0 {
    return Err(UnsupportedPresetDictionary)
  }

  let reader : BitReader = {
    data,
    end: data.length() - 4,
    byte_offset: 2,
    bit_offset: 0,
  }
  let output : Array[Byte] = []
  let mut final_block = false
  while !final_block {
    final_block = match reader.read_bits(1) {
      Ok(value) => value != 0
      Err(error) => return Err(error)
    }
    let block_type = match reader.read_bits(2) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if block_type == 0 {
      match decode_stored_block(reader, output, max_output_size) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    } else if block_type == 1 {
      let literal_tree = match fixed_literal_tree() {
        Ok(tree) => tree
        Err(error) => return Err(error)
      }
      let distance_tree = match fixed_distance_tree() {
        Ok(tree) => Some(tree)
        Err(error) => return Err(error)
      }
      match
        decode_compressed_block(
          reader, output, literal_tree, distance_tree, max_output_size,
        ) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    } else if block_type == 2 {
      let (literal_tree, distance_tree) = match read_dynamic_trees(reader) {
        Ok(trees) => trees
        Err(error) => return Err(error)
      }
      match
        decode_compressed_block(
          reader, output, literal_tree, distance_tree, max_output_size,
        ) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    } else {
      return Err(InvalidDeflateBlockType(block_type))
    }
  }

  let consumed = if reader.bit_offset == 0 {
    reader.byte_offset
  } else {
    reader.byte_offset + 1
  }
  if consumed != reader.end {
    return Err(TrailingDeflateData(reader.end - consumed))
  }

  let inflated = Bytes::from_array(output)
  let expected = read_uint32_be(data, data.length() - 4)
  let actual = adler32(inflated)
  if expected != actual {
    return Err(AdlerMismatch(expected, actual))
  }
  Ok(inflated)
}
