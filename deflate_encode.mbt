///|
priv struct DeflateBitWriter {
  emit_byte : (Byte) -> Unit
  mut current : Int
  mut used : Int
}

///|
fn DeflateBitWriter::write_bits(
  self : DeflateBitWriter,
  value : Int,
  count : Int,
) -> Unit {
  for shift = 0; shift < count; shift = shift + 1 {
    self.current = self.current | (((value >> shift) & 1) << self.used)
    self.used = self.used + 1
    if self.used == 8 {
      (self.emit_byte)(self.current.to_byte())
      self.current = 0
      self.used = 0
    }
  }
}

///|
fn DeflateBitWriter::finish(self : DeflateBitWriter) -> Unit {
  if self.used != 0 {
    (self.emit_byte)(self.current.to_byte())
    self.current = 0
    self.used = 0
  }
}

///|
fn DeflateBitWriter::emit_complete_byte(
  self : DeflateBitWriter,
  value : Byte,
) -> Unit {
  (self.emit_byte)(value)
}

///|
fn deflate_write_fixed_symbol(writer : DeflateBitWriter, symbol : Int) -> Unit {
  let (canonical, bit_count) = if symbol <= 143 {
    (0x30 + symbol, 8)
  } else if symbol <= 255 {
    (0x190 + symbol - 144, 9)
  } else if symbol <= 279 {
    (symbol - 256, 7)
  } else {
    (0xc0 + symbol - 280, 8)
  }
  writer.write_bits(reverse_low_bits(canonical, bit_count), bit_count)
}

///|
fn deflate_fixed_symbol_bit_count(symbol : Int) -> Int {
  if symbol <= 143 {
    8
  } else if symbol <= 255 {
    9
  } else if symbol <= 279 {
    7
  } else {
    8
  }
}

///|
fn deflate_length_index(length : Int) -> Int {
  let mut index = 0
  while index + 1 < length_bases.length() && length >= length_bases[index + 1] {
    index = index + 1
  }
  index
}

///|
fn deflate_write_length(writer : DeflateBitWriter, length : Int) -> Unit {
  let index = deflate_length_index(length)
  deflate_write_fixed_symbol(writer, 257 + index)
  let extra_bits = length_extra_bits[index]
  if extra_bits != 0 {
    writer.write_bits(length - length_bases[index], extra_bits)
  }
}

///|
fn deflate_distance_symbol(distance : Int) -> Int {
  let mut symbol = 0
  while symbol + 1 < distance_bases.length() &&
        distance >= distance_bases[symbol + 1] {
    symbol = symbol + 1
  }
  symbol
}

///|
fn deflate_write_distance(writer : DeflateBitWriter, distance : Int) -> Unit {
  let symbol = deflate_distance_symbol(distance)
  writer.write_bits(reverse_low_bits(symbol, 5), 5)
  let extra_bits = distance_extra_bits[symbol]
  if extra_bits != 0 {
    writer.write_bits(distance - distance_bases[symbol], extra_bits)
  }
}

///|
fn deflate_match_bit_cost(length : Int, distance : Int) -> Int {
  let length_index = deflate_length_index(length)
  let distance_symbol = deflate_distance_symbol(distance)
  deflate_fixed_symbol_bit_count(257 + length_index) +
  length_extra_bits[length_index] +
  5 +
  distance_extra_bits[distance_symbol]
}

///|
fn deflate_hash(data : Bytes, offset : Int) -> Int {
  let first = data.unsafe_get(offset).to_int()
  let second = data.unsafe_get(offset + 1).to_int()
  let third = data.unsafe_get(offset + 2).to_int()
  ((first * 251 + second) * 251 + third) & 0x7fff
}

///|
fn deflate_insert(
  data : Bytes,
  offset : Int,
  head : Array[Int],
  previous : Array[Int],
) -> Unit {
  if offset + 2 < data.length() {
    let hash = deflate_hash(data, offset)
    previous[offset] = head[hash]
    head[hash] = offset
  }
}

///|
fn deflate_find_match(
  data : Bytes,
  offset : Int,
  head : Array[Int],
  previous : Array[Int],
) -> (Int, Int, Int) {
  if offset + 2 >= data.length() {
    return (0, 0, 0)
  }
  let mut candidate = head[deflate_hash(data, offset)]
  let mut best_length = 0
  let mut best_distance = 0
  let mut best_savings = 0
  let remaining = data.length() - offset
  let maximum_length = if remaining > 258 { 258 } else { remaining }
  let mut attempts = 0
  while candidate >= 0 && attempts < 128 {
    let distance = offset - candidate
    if distance > 32768 {
      break
    }
    let mut length = 0
    let mut literal_bits = 0
    while length < maximum_length &&
          data.unsafe_get(candidate + length) ==
          data.unsafe_get(offset + length) {
      literal_bits = literal_bits +
        deflate_fixed_symbol_bit_count(
          data.unsafe_get(offset + length).to_int(),
        )
      length = length + 1
    }
    if length >= 3 {
      let savings = literal_bits - deflate_match_bit_cost(length, distance)
      if savings > best_savings ||
        (
          savings == best_savings &&
          (
            length > best_length ||
            (length == best_length && distance < best_distance)
          )
        ) {
        best_length = length
        best_distance = distance
        best_savings = savings
      }
      if length == 258 && savings == best_savings {
        break
      }
    }
    candidate = previous[candidate]
    attempts = attempts + 1
  }
  if best_savings > 0 {
    (best_length, best_distance, best_savings)
  } else {
    (0, 0, 0)
  }
}

///|
fn deflate_write_fixed_block(
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
fn deflate_write_stored_blocks(
  writer : DeflateBitWriter,
  data : Bytes,
  is_final : Bool,
) -> Unit {
  let mut offset = 0
  if data.length() == 0 {
    writer.write_bits(if is_final { 1 } else { 0 }, 1)
    writer.write_bits(0, 2)
    writer.finish()
    writer.emit_complete_byte(b'\x00')
    writer.emit_complete_byte(b'\x00')
    writer.emit_complete_byte(b'\xff')
    writer.emit_complete_byte(b'\xff')
  }
  while offset < data.length() {
    let remaining = data.length() - offset
    let block_length = if remaining > 65535 { 65535 } else { remaining }
    let block_is_final = is_final && offset + block_length == data.length()
    writer.write_bits(if block_is_final { 1 } else { 0 }, 1)
    writer.write_bits(0, 2)
    writer.finish()
    writer.emit_complete_byte(block_length.to_byte())
    writer.emit_complete_byte((block_length >> 8).to_byte())
    let inverse = block_length ^ 0xffff
    writer.emit_complete_byte(inverse.to_byte())
    writer.emit_complete_byte((inverse >> 8).to_byte())
    for index = 0; index < block_length; index = index + 1 {
      writer.emit_complete_byte(data.unsafe_get(offset + index))
    }
    offset = offset + block_length
  }
}

///|
fn deflate_stored_blocks_bit_count(initial_used : Int, length : Int) -> Int {
  let block_count = if length == 0 { 1 } else { (length + 65534) / 65535 }
  let first_padding = (8 - (initial_used + 3) % 8) % 8
  3 + first_padding + 32 + length * 8 + (block_count - 1) * 40
}

///|
fn deflate_write_auto_block(
  writer : DeflateBitWriter,
  data : Bytes,
  is_final : Bool,
) -> Bool {
  if data.length() > (0x7fffffff - 64) / 9 {
    deflate_write_stored_blocks(writer, data, is_final)
    return false
  }
  let candidate : Array[Byte] = []
  let probe : DeflateBitWriter = {
    emit_byte: byte => candidate.push(byte),
    current: writer.current,
    used: writer.used,
  }
  let initial_used = writer.used
  deflate_write_fixed_block(probe, data, is_final)
  let fixed_bits = candidate.length() * 8 + probe.used - initial_used
  let stored_bits = deflate_stored_blocks_bit_count(initial_used, data.length())
  if fixed_bits < stored_bits {
    for byte in candidate {
      writer.emit_complete_byte(byte)
    }
    writer.current = probe.current
    writer.used = probe.used
    true
  } else {
    deflate_write_stored_blocks(writer, data, is_final)
    false
  }
}

///|
fn deflate_fixed_payload(data : Bytes) -> Bytes {
  let output : Array[Byte] = []
  let writer : DeflateBitWriter = {
    emit_byte: byte => output.push(byte),
    current: 0,
    used: 0,
  }
  deflate_write_fixed_block(writer, data, true)
  writer.finish()
  Bytes::from_array(output)
}

///|
/// Compresses bytes as one deterministic fixed-Huffman zlib stream.
pub fn compress_zlib_fixed(data : Bytes) -> Bytes {
  let output : Array[Byte] = [b'\x78', b'\x01']
  encode_append_bytes(output, deflate_fixed_payload(data))
  encode_append_uint32_be(output, adler32(data))
  Bytes::from_array(output)
}
