///|
/// Canonical Huffman codes stored in DEFLATE's least-significant-bit order.
priv struct DeflateHuffmanCodes {
  lengths : Array[Int]
  codes : Array[Int]
}

///|
/// One code-length alphabet symbol and its optional repeat payload.
priv struct DeflateCodeLengthRun {
  symbol : Int
  extra_value : Int
  extra_bits : Int
}

///|
let deflate_code_length_order : Array[Int] = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
]

///|
fn deflate_copy_frequencies(frequencies : Array[Int]) -> Array[Int] {
  let copy = Array::make(frequencies.length(), 0)
  for index = 0; index < frequencies.length(); index = index + 1 {
    copy[index] = frequencies[index]
  }
  copy
}

///|
fn deflate_ensure_two_symbols(frequencies : Array[Int]) -> Unit {
  let mut active = 0
  for frequency in frequencies {
    if frequency > 0 {
      active = active + 1
    }
  }
  if active == 0 {
    frequencies[0] = 1
    frequencies[1] = 1
  } else if active == 1 {
    for symbol = 0; symbol < frequencies.length(); symbol = symbol + 1 {
      if frequencies[symbol] == 0 {
        frequencies[symbol] = 1
        break
      }
    }
  }
}

///|
fn deflate_huffman_node_is_less(
  left : Int,
  right : Int,
  weights : Array[Int],
  orders : Array[Int],
) -> Bool {
  weights[left] < weights[right] ||
  (weights[left] == weights[right] && orders[left] < orders[right]) ||
  (
    weights[left] == weights[right] &&
    orders[left] == orders[right] &&
    left < right
  )
}

///|
fn deflate_sort_symbols_by_frequency(
  symbols : Array[Int],
  frequencies : Array[Int],
) -> Unit {
  for index = 1; index < symbols.length(); index = index + 1 {
    let symbol = symbols[index]
    let mut position = index
    while position > 0 {
      let previous = symbols[position - 1]
      if frequencies[previous] < frequencies[symbol] ||
        (frequencies[previous] == frequencies[symbol] && previous < symbol) {
        break
      }
      symbols[position] = previous
      position = position - 1
    }
    symbols[position] = symbol
  }
}

///|
/// Build deterministic Huffman lengths and enforce DEFLATE's depth limit.
fn deflate_build_code_lengths(
  source_frequencies : Array[Int],
  max_bits : Int,
) -> Array[Int] {
  let frequencies = deflate_copy_frequencies(source_frequencies)
  deflate_ensure_two_symbols(frequencies)
  let leaf_nodes = Array::make(frequencies.length(), -1)
  let weights : Array[Int] = []
  let parents : Array[Int] = []
  let orders : Array[Int] = []
  let mut roots = 0
  for symbol = 0; symbol < frequencies.length(); symbol = symbol + 1 {
    if frequencies[symbol] > 0 {
      leaf_nodes[symbol] = weights.length()
      weights.push(frequencies[symbol])
      parents.push(-1)
      orders.push(symbol)
      roots = roots + 1
    }
  }
  while roots > 1 {
    let mut first = -1
    for node = 0; node < weights.length(); node = node + 1 {
      if parents[node] == -1 &&
        (
          first < 0 ||
          deflate_huffman_node_is_less(node, first, weights, orders)
        ) {
        first = node
      }
    }
    let mut second = -1
    for node = 0; node < weights.length(); node = node + 1 {
      if node != first &&
        parents[node] == -1 &&
        (
          second < 0 ||
          deflate_huffman_node_is_less(node, second, weights, orders)
        ) {
        second = node
      }
    }
    let parent = weights.length()
    let combined_weight = if weights[first] > 0x7fffffff - weights[second] {
      0x7fffffff
    } else {
      weights[first] + weights[second]
    }
    weights.push(combined_weight)
    parents.push(-1)
    orders.push(
      if orders[first] < orders[second] {
        orders[first]
      } else {
        orders[second]
      },
    )
    parents[first] = parent
    parents[second] = parent
    roots = roots - 1
  }

  let lengths = Array::make(frequencies.length(), 0)
  let bit_counts = Array::make(max_bits + 1, 0)
  for symbol = 0; symbol < frequencies.length(); symbol = symbol + 1 {
    let leaf = leaf_nodes[symbol]
    if leaf >= 0 {
      let mut depth = 0
      let mut node = leaf
      while parents[node] >= 0 {
        depth = depth + 1
        node = parents[node]
      }
      if depth > max_bits {
        depth = max_bits
      }
      lengths[symbol] = depth
      bit_counts[depth] = bit_counts[depth] + 1
    }
  }

  let maximum_capacity = 1 << max_bits
  let mut used_capacity = 0
  for bits = 1; bits <= max_bits; bits = bits + 1 {
    used_capacity = used_capacity + bit_counts[bits] * (1 << (max_bits - bits))
  }
  while used_capacity > maximum_capacity {
    let mut bits = max_bits - 1
    while bits > 0 && bit_counts[bits] == 0 {
      bits = bits - 1
    }
    if bits == 0 || bit_counts[max_bits] == 0 {
      abort("unable to limit Huffman code lengths")
    }
    bit_counts[bits] = bit_counts[bits] - 1
    bit_counts[bits + 1] = bit_counts[bits + 1] + 2
    bit_counts[max_bits] = bit_counts[max_bits] - 1
    used_capacity = used_capacity - 1
  }
  let symbols : Array[Int] = []
  for symbol = 0; symbol < frequencies.length(); symbol = symbol + 1 {
    if frequencies[symbol] > 0 {
      symbols.push(symbol)
    }
  }
  deflate_sort_symbols_by_frequency(symbols, frequencies)
  let mut position = 0
  for bits = max_bits; bits > 0; bits = bits - 1 {
    for index = 0; index < bit_counts[bits]; index = index + 1 {
      lengths[symbols[position]] = bits
      position = position + 1
    }
  }
  lengths
}

///|
fn deflate_make_huffman_codes(
  lengths : Array[Int],
  max_bits : Int,
) -> DeflateHuffmanCodes {
  let counts = Array::make(max_bits + 1, 0)
  for length in lengths {
    if length > 0 {
      counts[length] = counts[length] + 1
    }
  }
  let next_codes = Array::make(max_bits + 1, 0)
  let mut code = 0
  for bits = 1; bits <= max_bits; bits = bits + 1 {
    code = (code + counts[bits - 1]) << 1
    next_codes[bits] = code
  }
  let codes = Array::make(lengths.length(), 0)
  for symbol = 0; symbol < lengths.length(); symbol = symbol + 1 {
    let length = lengths[symbol]
    if length > 0 {
      codes[symbol] = reverse_low_bits(next_codes[length], length)
      next_codes[length] = next_codes[length] + 1
    }
  }
  { lengths, codes, }
}

///|
fn DeflateHuffmanCodes::write_symbol(
  self : DeflateHuffmanCodes,
  writer : DeflateBitWriter,
  symbol : Int,
) -> Unit {
  writer.write_bits(self.codes[symbol], self.lengths[symbol])
}

///|
fn deflate_token_frequencies(
  tokens : Array[Lz77Token],
) -> (Array[Int], Array[Int]) {
  let literal_frequencies = Array::make(286, 0)
  let distance_frequencies = Array::make(30, 0)
  literal_frequencies[256] = 1
  for token in tokens {
    match token {
      Lz77Literal(byte) => {
        let symbol = byte.to_int()
        literal_frequencies[symbol] = literal_frequencies[symbol] + 1
      }
      Lz77Match(length, distance) => {
        let length_symbol = 257 + deflate_length_index(length)
        let distance_symbol = deflate_distance_symbol(distance)
        literal_frequencies[length_symbol] = literal_frequencies[length_symbol] +
          1
        distance_frequencies[distance_symbol] = distance_frequencies[distance_symbol] +
          1
      }
    }
  }
  (literal_frequencies, distance_frequencies)
}

///|
fn deflate_trimmed_length_count(lengths : Array[Int], minimum : Int) -> Int {
  let mut count = lengths.length()
  while count > minimum && lengths[count - 1] == 0 {
    count = count - 1
  }
  count
}

///|
fn deflate_push_code_length_run(
  output : Array[DeflateCodeLengthRun],
  symbol : Int,
  extra_value : Int,
  extra_bits : Int,
) -> Unit {
  output.push({ symbol, extra_value, extra_bits, })
}

///|
fn deflate_encode_code_length_runs(
  lengths : Array[Int],
) -> Array[DeflateCodeLengthRun] {
  let output : Array[DeflateCodeLengthRun] = []
  let mut offset = 0
  while offset < lengths.length() {
    let value = lengths[offset]
    let mut run = 1
    while offset + run < lengths.length() && lengths[offset + run] == value {
      run = run + 1
    }
    if value == 0 {
      let mut remaining = run
      while remaining >= 11 {
        let count = if remaining > 138 { 138 } else { remaining }
        deflate_push_code_length_run(output, 18, count - 11, 7)
        remaining = remaining - count
      }
      if remaining >= 3 {
        let count = if remaining > 10 { 10 } else { remaining }
        deflate_push_code_length_run(output, 17, count - 3, 3)
        remaining = remaining - count
      }
      while remaining > 0 {
        deflate_push_code_length_run(output, 0, 0, 0)
        remaining = remaining - 1
      }
    } else {
      deflate_push_code_length_run(output, value, 0, 0)
      let mut remaining = run - 1
      while remaining >= 3 {
        let count = if remaining > 6 { 6 } else { remaining }
        deflate_push_code_length_run(output, 16, count - 3, 2)
        remaining = remaining - count
      }
      while remaining > 0 {
        deflate_push_code_length_run(output, value, 0, 0)
        remaining = remaining - 1
      }
    }
    offset = offset + run
  }
  output
}

///|
fn deflate_write_dynamic_tokens(
  writer : DeflateBitWriter,
  tokens : Array[Lz77Token],
  literal_codes : DeflateHuffmanCodes,
  distance_codes : DeflateHuffmanCodes,
) -> Unit {
  for token in tokens {
    match token {
      Lz77Literal(byte) => literal_codes.write_symbol(writer, byte.to_int())
      Lz77Match(length, distance) => {
        let length_index = deflate_length_index(length)
        literal_codes.write_symbol(writer, 257 + length_index)
        let length_bits = length_extra_bits[length_index]
        if length_bits > 0 {
          writer.write_bits(length - length_bases[length_index], length_bits)
        }
        let distance_symbol = deflate_distance_symbol(distance)
        distance_codes.write_symbol(writer, distance_symbol)
        let distance_bits = distance_extra_bits[distance_symbol]
        if distance_bits > 0 {
          writer.write_bits(
            distance - distance_bases[distance_symbol],
            distance_bits,
          )
        }
      }
    }
  }
  literal_codes.write_symbol(writer, 256)
}

///|
fn deflate_write_dynamic_block(
  writer : DeflateBitWriter,
  tokens : Array[Lz77Token],
  is_final : Bool,
) -> Unit {
  let (literal_frequencies, distance_frequencies) = deflate_token_frequencies(
    tokens,
  )
  let literal_lengths = deflate_build_code_lengths(literal_frequencies, 15)
  let distance_lengths = deflate_build_code_lengths(distance_frequencies, 15)
  let literal_count = deflate_trimmed_length_count(literal_lengths, 257)
  let distance_count = deflate_trimmed_length_count(distance_lengths, 1)
  let combined_lengths : Array[Int] = []
  combined_lengths.reserve_capacity(literal_count + distance_count)
  for index = 0; index < literal_count; index = index + 1 {
    combined_lengths.push(literal_lengths[index])
  }
  for index = 0; index < distance_count; index = index + 1 {
    combined_lengths.push(distance_lengths[index])
  }
  let runs = deflate_encode_code_length_runs(combined_lengths)
  let code_length_frequencies = Array::make(19, 0)
  for run in runs {
    code_length_frequencies[run.symbol] = code_length_frequencies[run.symbol] +
      1
  }
  let code_length_lengths = deflate_build_code_lengths(
    code_length_frequencies, 7,
  )
  let mut code_length_count = 19
  while code_length_count > 4 &&
        code_length_lengths[deflate_code_length_order[code_length_count - 1]] ==
        0 {
    code_length_count = code_length_count - 1
  }
  let literal_codes = deflate_make_huffman_codes(literal_lengths, 15)
  let distance_codes = deflate_make_huffman_codes(distance_lengths, 15)
  let code_length_codes = deflate_make_huffman_codes(code_length_lengths, 7)

  writer.write_bits(if is_final { 1 } else { 0 }, 1)
  writer.write_bits(2, 2)
  writer.write_bits(literal_count - 257, 5)
  writer.write_bits(distance_count - 1, 5)
  writer.write_bits(code_length_count - 4, 4)
  for index = 0; index < code_length_count; index = index + 1 {
    writer.write_bits(code_length_lengths[deflate_code_length_order[index]], 3)
  }
  for run in runs {
    code_length_codes.write_symbol(writer, run.symbol)
    if run.extra_bits > 0 {
      writer.write_bits(run.extra_value, run.extra_bits)
    }
  }
  deflate_write_dynamic_tokens(writer, tokens, literal_codes, distance_codes)
}

///|
fn deflate_dynamic_payload(data : Bytes) -> Bytes {
  let output : Array[Byte] = []
  let writer : DeflateBitWriter = {
    emit_byte: byte => output.push(byte),
    current: 0,
    used: 0,
  }
  deflate_write_dynamic_block(writer, deflate_tokenize_lz77(data), true)
  writer.finish()
  Bytes::from_array(output)
}

///|
/// Compresses bytes as one deterministic dynamic-Huffman zlib stream.
pub fn compress_zlib_dynamic(data : Bytes) -> Bytes {
  let output : Array[Byte] = [b'\x78', b'\x01']
  encode_append_bytes(output, deflate_dynamic_payload(data))
  encode_append_uint32_be(output, adler32(data))
  Bytes::from_array(output)
}
