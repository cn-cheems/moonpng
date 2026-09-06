///|
/// Errors reported while encoding PNG image data.
pub(all) enum EncodeError {
  EncodeInvalidDimensions(UInt, UInt)
  EncodeImageTooLarge(UInt, UInt)
  EncodePixelLengthMismatch(Int, Int)
} derive(Debug, Eq)

///|
/// Return a concise human-readable explanation for an encode error.
pub fn EncodeError::message(self : EncodeError) -> String {
  match self {
    EncodeInvalidDimensions(width, height) =>
      "PNG dimensions must be non-zero, got \{width}x\{height}"
    EncodeImageTooLarge(width, height) =>
      "image \{width}x\{height} is too large for an in-memory PNG"
    EncodePixelLengthMismatch(expected, actual) =>
      "RGBA8 input requires \{expected} bytes, got \{actual}"
  }
}
