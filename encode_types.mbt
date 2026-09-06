///|
/// Errors reported while encoding PNG image data.
pub(all) enum EncodeError {
  EncodeInvalidDimensions(UInt, UInt)
  EncodeImageTooLarge(UInt, UInt)
  EncodePixelLengthMismatch(Int, Int)
} derive(Debug, Eq)

///|
/// Scanline filtering strategy used by the PNG encoder.
pub(all) enum FilterStrategy {
  FilterNone
  FilterSub
  FilterUp
  FilterAverage
  FilterPaeth
  FilterAdaptive
} derive(Debug, Eq)

///|
/// Options controlling deterministic PNG encoding.
pub(all) struct EncodeOptions {
  filter_strategy : FilterStrategy
} derive(Debug, Eq)

///|
/// Return the recommended deterministic encoder options.
pub fn default_encode_options() -> EncodeOptions {
  { filter_strategy: FilterAdaptive, }
}

///|
/// In-memory pixel layout accepted by the PNG encoder.
pub(all) enum PixelFormat {
  PixelGray8
  PixelGrayAlpha8
  PixelRgb8
  PixelRgba8
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
      "pixel input requires \{expected} bytes, got \{actual}"
  }
}
