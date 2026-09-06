///|
/// Conservative resource limits used by the PNG decoder.
pub(all) struct DecodeLimits {
  max_chunk_size : Int
  max_chunks : Int
  max_compressed_size : Int
  max_inflated_size : Int
  max_pixels : Int
} derive(Debug, Eq)

///|
/// Return the default limits used by [`decode`].
pub fn default_decode_limits() -> DecodeLimits {
  {
    max_chunk_size: 64 * 1024 * 1024,
    max_chunks: 4096,
    max_compressed_size: 128 * 1024 * 1024,
    max_inflated_size: 256 * 1024 * 1024,
    max_pixels: 64 * 1024 * 1024,
  }
}

///|
/// One 8-bit red, green, blue, and alpha pixel.
pub(all) struct Rgba8 {
  red : Byte
  green : Byte
  blue : Byte
  alpha : Byte
} derive(Debug, Eq)

///|
/// A decoded image in row-major RGBA8 format.
pub(all) struct DecodedImage {
  width : UInt
  height : UInt
  pixels : Bytes
} derive(Debug, Eq)

///|
/// Return a pixel when `(x, y)` is inside the image.
pub fn DecodedImage::pixel_at(self : DecodedImage, x : Int, y : Int) -> Rgba8? {
  if x < 0 ||
    y < 0 ||
    x >= self.width.reinterpret_as_int() ||
    y >= self.height.reinterpret_as_int() {
    return None
  }
  let offset = (y * self.width.reinterpret_as_int() + x) * 4
  Some({
    red: self.pixels.unsafe_get(offset),
    green: self.pixels.unsafe_get(offset + 1),
    blue: self.pixels.unsafe_get(offset + 2),
    alpha: self.pixels.unsafe_get(offset + 3),
  })
}

///|
/// Errors reported while inflating or decoding PNG image data.
pub(all) enum DecodeError {
  InvalidContainer(PngError)
  InvalidDecodeLimits
  ImageTooLarge(UInt, UInt, Int)
  CompressedDataTooLarge(Int)
  UnsupportedBitDepth(Byte)
  UnsupportedColorType(Byte)
  UnsupportedInterlace(Byte)
  MissingIdatData
  InvalidZlibHeader
  UnsupportedPresetDictionary
  TruncatedDeflate
  InvalidDeflateBlockType(Int)
  InvalidStoredBlockLength
  InvalidHuffmanTree
  InvalidHuffmanCode
  InvalidCodeLengthRepeat
  InvalidLengthSymbol(Int)
  InvalidDistanceSymbol(Int)
  InvalidBackReference(Int, Int)
  OutputLimitExceeded(Int)
  TrailingDeflateData(Int)
  AdlerMismatch(UInt, UInt)
  InvalidInflatedSize(Int, Int)
  InvalidFilter(Byte, Int)
  UnsupportedCriticalChunk(String)
  MissingPalette
  DuplicatePalette
  InvalidPaletteLength(Int)
  PaletteTooLarge(Int, Byte)
  UnexpectedPalette(Byte)
  InvalidChunkOrder(String)
  PaletteIndexOutOfRange(Int, Int, Int)
  DuplicateTransparency
  InvalidTransparency(Byte, Int)
} derive(Debug, Eq)

///|
/// Return a concise human-readable explanation for a decode error.
pub fn DecodeError::message(self : DecodeError) -> String {
  match self {
    InvalidContainer(error) => error.message()
    InvalidDecodeLimits => "decode limits must all be positive"
    ImageTooLarge(width, height, limit) =>
      "image \{width}x\{height} exceeds the \{limit}-pixel limit"
    CompressedDataTooLarge(limit) =>
      "combined IDAT data exceeds the \{limit}-byte limit"
    UnsupportedBitDepth(depth) =>
      "pixel decoding supports 1-, 2-, 4-, and 8-bit samples where allowed by the color type; got \{depth.to_uint()}"
    UnsupportedColorType(color) =>
      "pixel decoding currently supports color types 0, 2, 3, 4, and 6; got \{color.to_uint()}"
    UnsupportedInterlace(value) =>
      "pixel decoding currently supports non-interlaced PNGs, got interlace method \{value.to_uint()}"
    MissingIdatData => "PNG contains no compressed IDAT payload"
    InvalidZlibHeader => "invalid or unsupported zlib header"
    UnsupportedPresetDictionary => "zlib preset dictionaries are not supported"
    TruncatedDeflate => "compressed DEFLATE stream ended unexpectedly"
    InvalidDeflateBlockType(kind) => "reserved DEFLATE block type \{kind}"
    InvalidStoredBlockLength =>
      "stored DEFLATE block has an invalid LEN/NLEN pair"
    InvalidHuffmanTree => "invalid DEFLATE Huffman tree"
    InvalidHuffmanCode => "invalid DEFLATE Huffman code"
    InvalidCodeLengthRepeat => "invalid DEFLATE code-length repeat"
    InvalidLengthSymbol(symbol) => "invalid DEFLATE length symbol \{symbol}"
    InvalidDistanceSymbol(symbol) => "invalid DEFLATE distance symbol \{symbol}"
    InvalidBackReference(distance, available) =>
      "DEFLATE back-reference distance \{distance} exceeds \{available} output bytes"
    OutputLimitExceeded(limit) =>
      "inflated data exceeds the \{limit}-byte output limit"
    TrailingDeflateData(count) =>
      "zlib stream contains \{count} trailing compressed bytes"
    AdlerMismatch(expected, actual) =>
      "zlib Adler-32 mismatch: stream=\{expected}, computed=\{actual}"
    InvalidInflatedSize(expected, actual) =>
      "PNG scanlines require \{expected} inflated bytes, got \{actual}"
    InvalidFilter(filter, row) =>
      "unsupported PNG filter \{filter.to_uint()} on row \{row}"
    UnsupportedCriticalChunk(kind) => "unsupported critical PNG chunk \{kind}"
    MissingPalette => "indexed-color PNG is missing its required PLTE chunk"
    DuplicatePalette => "PNG contains more than one PLTE chunk"
    InvalidPaletteLength(length) =>
      "PLTE length must be a non-zero multiple of three up to 768 bytes, got \{length}"
    PaletteTooLarge(entries, depth) =>
      "PLTE has \{entries} entries but bit depth \{depth.to_uint()} permits at most \{1 << depth.to_int()}"
    UnexpectedPalette(color) =>
      "PLTE is not permitted for color type \{color.to_uint()}"
    InvalidChunkOrder(kind) => "\{kind} must appear before the first IDAT chunk"
    PaletteIndexOutOfRange(index, x, y) =>
      "palette index \{index} at (\{x}, \{y}) has no PLTE entry"
    DuplicateTransparency => "PNG contains more than one tRNS chunk"
    InvalidTransparency(color, length) =>
      "invalid tRNS length \{length} for color type \{color.to_uint()}"
  }
}
