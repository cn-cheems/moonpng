///|
/// Metadata for one validated PNG chunk.
pub(all) struct ChunkInfo {
  offset : Int
  kind : String
  data_offset : Int
  length : Int
  crc_read : UInt
  crc_computed : UInt
  is_critical : Bool
  is_private : Bool
  is_safe_to_copy : Bool
} derive(Debug, Eq)

///|
/// Structural information extracted from a PNG byte stream.
pub(all) struct PngInfo {
  width : UInt
  height : UInt
  bit_depth : Byte
  color_type : Byte
  compression_method : Byte
  filter_method : Byte
  interlace_method : Byte
  chunks : Array[ChunkInfo]
} derive(Debug, Eq)

///|
/// Errors reported by the strict structural PNG inspector.
pub(all) enum PngError {
  InputTooShort(Int)
  InvalidSignature
  InvalidLimits
  TooManyChunks(Int)
  TruncatedChunkHeader(Int)
  ChunkLengthOverflow(UInt, Int)
  ChunkTooLarge(String, Int, Int)
  TruncatedChunk(String, Int, Int, Int)
  InvalidChunkType(Int)
  InvalidReservedBit(String, Int)
  CrcMismatch(String, Int, UInt, UInt)
  IhdrNotFirst
  DuplicateIhdr(Int)
  InvalidIhdrLength(Int)
  InvalidDimensions(UInt, UInt)
  InvalidColorFormat(Byte, Byte)
  InvalidCompressionMethod(Byte)
  InvalidFilterMethod(Byte)
  InvalidInterlaceMethod(Byte)
  MissingIhdr
  MissingIdat
  InvalidIendLength(Int)
  MissingIend
  TrailingData(Int)
} derive(Debug, Eq)

///|
/// Return a concise human-readable explanation for an inspection error.
pub fn PngError::message(self : PngError) -> String {
  match self {
    InputTooShort(actual) =>
      "PNG input is shorter than the 8-byte signature: \{actual} bytes"
    InvalidSignature => "PNG signature does not match 89 50 4E 47 0D 0A 1A 0A"
    InvalidLimits => "inspection limits must be positive"
    TooManyChunks(limit) => "PNG contains more than the allowed \{limit} chunks"
    TruncatedChunkHeader(offset) =>
      "truncated PNG chunk header at byte \{offset}"
    ChunkLengthOverflow(length, offset) =>
      "chunk at byte \{offset} declares an unsupported length of \{length}"
    ChunkTooLarge(kind, length, limit) =>
      "\{kind} chunk exceeds the \{limit}-byte limit: \{length} bytes"
    TruncatedChunk(kind, offset, expected, actual) =>
      "\{kind} chunk at byte \{offset} ends at \{expected}, input length is \{actual}"
    InvalidChunkType(offset) =>
      "chunk type at byte \{offset} must contain four ASCII letters"
    InvalidReservedBit(kind, offset) =>
      "\{kind} chunk at byte \{offset} uses the reserved lowercase third letter"
    CrcMismatch(kind, offset, expected, actual) =>
      "CRC mismatch for \{kind} at byte \{offset}: file=\{expected}, computed=\{actual}"
    IhdrNotFirst => "IHDR must be the first PNG chunk"
    DuplicateIhdr(offset) => "duplicate IHDR chunk at byte \{offset}"
    InvalidIhdrLength(length) => "IHDR length must be 13 bytes, got \{length}"
    InvalidDimensions(width, height) =>
      "PNG dimensions must be non-zero, got \{width}x\{height}"
    InvalidColorFormat(depth, color) =>
      "invalid PNG bit-depth/color-type pair: depth=\{depth}, color_type=\{color}"
    InvalidCompressionMethod(value) =>
      "unsupported PNG compression method \{value}"
    InvalidFilterMethod(value) => "unsupported PNG filter method \{value}"
    InvalidInterlaceMethod(value) => "unsupported PNG interlace method \{value}"
    MissingIhdr => "PNG is missing its IHDR chunk"
    MissingIdat => "PNG is missing image data (IDAT)"
    InvalidIendLength(length) => "IEND length must be zero, got \{length}"
    MissingIend => "PNG is missing its IEND chunk"
    TrailingData(offset) => "unexpected data follows IEND at byte \{offset}"
  }
}

///|
let png_signature : Bytes = b"\x89PNG\r\n\x1a\n"

///|
fn has_png_signature(data : Bytes) -> Bool {
  if data.length() < png_signature.length() {
    return false
  }
  for i = 0; i < png_signature.length(); i = i + 1 {
    if data.unsafe_get(i) != png_signature.unsafe_get(i) {
      return false
    }
  }
  true
}

///|
fn is_ascii_letter(value : Byte) -> Bool {
  let value = value.to_uint()
  (value >= 65U && value <= 90U) || (value >= 97U && value <= 122U)
}

///|
fn chunk_type_string(data : Bytes, offset : Int) -> String {
  let builder = StringBuilder(size_hint=4)
  for i = 0; i < 4; i = i + 1 {
    builder.write_char(data.unsafe_get(offset + i).to_char())
  }
  builder.to_string()
}

///|
fn color_format_is_valid(bit_depth : Byte, color_type : Byte) -> Bool {
  let depth = bit_depth.to_uint()
  match color_type.to_uint() {
    0U =>
      depth == 1U || depth == 2U || depth == 4U || depth == 8U || depth == 16U
    2U => depth == 8U || depth == 16U
    3U => depth == 1U || depth == 2U || depth == 4U || depth == 8U
    4U => depth == 8U || depth == 16U
    6U => depth == 8U || depth == 16U
    _ => false
  }
}

///|
fn crc32_range(data : Bytes, start : Int, length : Int) -> UInt {
  let mut crc = 0xffffffffU
  for i = start; i < start + length; i = i + 1 {
    let mut current = crc ^ data.unsafe_get(i).to_uint()
    for bit = 0; bit < 8; bit = bit + 1 {
      current = if (current & 1U) != 0U {
        (current >> 1) ^ 0xedb88320U
      } else {
        current >> 1
      }
    }
    crc = current
  }
  crc ^ 0xffffffffU
}

///|
/// Compute the ISO 3309/PNG CRC-32 checksum of `data`.
pub fn crc32(data : Bytes) -> UInt {
  crc32_range(data, 0, data.length())
}

///|
/// Inspect a PNG using conservative default resource limits.
///
/// This MVP validates the container structure and metadata. It does not yet
/// inflate IDAT data or return pixels.
pub fn inspect(data : Bytes) -> Result[PngInfo, PngError] {
  inspect_with_limits(data, max_chunk_size=64 * 1024 * 1024, max_chunks=4096)
}

///|
/// Inspect a PNG while bounding individual chunk size and total chunk count.
pub fn inspect_with_limits(
  data : Bytes,
  max_chunk_size~ : Int,
  max_chunks~ : Int,
) -> Result[PngInfo, PngError] {
  if max_chunk_size <= 0 || max_chunks <= 0 {
    return Err(InvalidLimits)
  }
  if data.length() < png_signature.length() {
    return Err(InputTooShort(data.length()))
  }
  if !has_png_signature(data) {
    return Err(InvalidSignature)
  }

  let chunks : Array[ChunkInfo] = []
  let mut offset = png_signature.length()
  let mut seen_ihdr = false
  let mut seen_idat = false
  let mut seen_iend = false
  let mut width = 0U
  let mut height = 0U
  let mut bit_depth = b'\x00'
  let mut color_type = b'\x00'
  let mut compression_method = b'\x00'
  let mut filter_method = b'\x00'
  let mut interlace_method = b'\x00'

  while offset < data.length() {
    if chunks.length() >= max_chunks {
      return Err(TooManyChunks(max_chunks))
    }
    if data.length() - offset < 12 {
      return Err(TruncatedChunkHeader(offset))
    }

    let length_u = data.unsafe_read_uint32_be(offset)
    if length_u > 0x7fffffffU {
      return Err(ChunkLengthOverflow(length_u, offset))
    }
    let length = length_u.reinterpret_as_int()
    let kind_offset = offset + 4
    for i = 0; i < 4; i = i + 1 {
      if !is_ascii_letter(data.unsafe_get(kind_offset + i)) {
        return Err(InvalidChunkType(offset))
      }
    }
    let kind = chunk_type_string(data, kind_offset)
    if length > max_chunk_size {
      return Err(ChunkTooLarge(kind, length, max_chunk_size))
    }
    if (data.unsafe_get(kind_offset + 2).to_uint() & 0x20U) != 0U {
      return Err(InvalidReservedBit(kind, offset))
    }
    if length > data.length() - offset - 12 {
      return Err(
        TruncatedChunk(kind, offset, offset + 12 + length, data.length()),
      )
    }

    let data_offset = offset + 8
    let crc_offset = data_offset + length
    let crc_read = data.unsafe_read_uint32_be(crc_offset)
    let crc_computed = crc32_range(data, kind_offset, 4 + length)
    if crc_read != crc_computed {
      return Err(CrcMismatch(kind, offset, crc_read, crc_computed))
    }

    if chunks.is_empty() && kind != "IHDR" {
      return Err(IhdrNotFirst)
    }
    if kind == "IHDR" {
      if seen_ihdr {
        return Err(DuplicateIhdr(offset))
      }
      if length != 13 {
        return Err(InvalidIhdrLength(length))
      }
      seen_ihdr = true
      width = data.unsafe_read_uint32_be(data_offset)
      height = data.unsafe_read_uint32_be(data_offset + 4)
      bit_depth = data.unsafe_get(data_offset + 8)
      color_type = data.unsafe_get(data_offset + 9)
      compression_method = data.unsafe_get(data_offset + 10)
      filter_method = data.unsafe_get(data_offset + 11)
      interlace_method = data.unsafe_get(data_offset + 12)
      if width == 0U || height == 0U {
        return Err(InvalidDimensions(width, height))
      }
      if !color_format_is_valid(bit_depth, color_type) {
        return Err(InvalidColorFormat(bit_depth, color_type))
      }
      if compression_method != b'\x00' {
        return Err(InvalidCompressionMethod(compression_method))
      }
      if filter_method != b'\x00' {
        return Err(InvalidFilterMethod(filter_method))
      }
      if interlace_method != b'\x00' && interlace_method != b'\x01' {
        return Err(InvalidInterlaceMethod(interlace_method))
      }
    } else if kind == "IDAT" {
      seen_idat = true
    } else if kind == "IEND" {
      if length != 0 {
        return Err(InvalidIendLength(length))
      }
      seen_iend = true
    }

    chunks.push({
      offset,
      kind,
      data_offset,
      length,
      crc_read,
      crc_computed,
      is_critical: (data.unsafe_get(kind_offset).to_uint() & 0x20U) == 0U,
      is_private: (data.unsafe_get(kind_offset + 1).to_uint() & 0x20U) != 0U,
      is_safe_to_copy: (data.unsafe_get(kind_offset + 3).to_uint() & 0x20U) !=
      0U,
    })
    offset = crc_offset + 4
    if seen_iend {
      if offset != data.length() {
        return Err(TrailingData(offset))
      }
      break
    }
  }

  if !seen_ihdr {
    return Err(MissingIhdr)
  }
  if !seen_idat {
    return Err(MissingIdat)
  }
  if !seen_iend {
    return Err(MissingIend)
  }
  Ok({
    width,
    height,
    bit_depth,
    color_type,
    compression_method,
    filter_method,
    interlace_method,
    chunks,
  })
}
