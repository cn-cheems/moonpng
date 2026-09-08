///|
/// On-disk representation used for a PNG text entry.
pub(all) enum TextFormat {
  TextLatin1
  TextLatin1Compressed
  TextInternational
  TextInternationalCompressed
} derive(Debug, Eq)

///|
/// One textual annotation stored in a tEXt, zTXt, or iTXt chunk.
///
/// `language_tag` and `translated_keyword` are used only by international
/// formats. The keyword always follows PNG's printable Latin-1 restrictions.
pub(all) struct TextEntry {
  format : TextFormat
  keyword : String
  text : String
  language_tag : String
  translated_keyword : String
} derive(Debug, Eq)

///|
/// Resource limits for text metadata extraction.
pub(all) struct TextLimits {
  max_entries : Int
  max_encoded_bytes : Int
  max_decoded_bytes : Int
} derive(Debug, Eq)

///|
/// Return conservative limits for text metadata in untrusted PNG files.
pub fn default_text_limits() -> TextLimits {
  {
    max_entries: 256,
    max_encoded_bytes: 16 * 1024 * 1024,
    max_decoded_bytes: 32 * 1024 * 1024,
  }
}

///|
/// Create a Latin-1 text entry.
pub fn latin1_text(
  keyword : String,
  text : String,
  compressed? : Bool = false,
) -> TextEntry {
  {
    format: if compressed {
      TextLatin1Compressed
    } else {
      TextLatin1
    },
    keyword,
    text,
    language_tag: "",
    translated_keyword: "",
  }
}

///|
/// Create an international UTF-8 text entry.
pub fn international_text(
  keyword : String,
  text : String,
  language_tag? : String = "",
  translated_keyword? : String = "",
  compressed? : Bool = false,
) -> TextEntry {
  {
    format: if compressed {
      TextInternationalCompressed
    } else {
      TextInternational
    },
    keyword,
    text,
    language_tag,
    translated_keyword,
  }
}

///|
/// Errors reported while reading or writing PNG text metadata.
pub(all) enum TextError {
  TextInvalidContainer(PngError)
  TextInvalidLimits
  TextTooManyEntries(Int)
  TextEncodedDataTooLarge(Int)
  TextDecodedDataTooLarge(Int)
  TextMalformedChunk(String, Int)
  TextInvalidKeyword(Int)
  TextInvalidLatin1(String)
  TextInvalidUtf8(String)
  TextInvalidLanguageTag(Int)
  TextUnexpectedInternationalFields(Int)
  TextInvalidCompressionFlag(Byte, Int)
  TextUnsupportedCompression(String, Byte, Int)
  TextDecompressionFailed(String, Int, DecodeError)
  TextOutputTooLarge
} derive(Debug, Eq)

///|
/// Return a concise human-readable explanation for a text metadata error.
pub fn TextError::message(self : TextError) -> String {
  match self {
    TextInvalidContainer(error) => error.message()
    TextInvalidLimits => "text metadata limits must all be positive"
    TextTooManyEntries(limit) =>
      "PNG contains more than the allowed \{limit} text entries"
    TextEncodedDataTooLarge(limit) =>
      "encoded text metadata exceeds the \{limit}-byte limit"
    TextDecodedDataTooLarge(limit) =>
      "decoded text metadata exceeds the \{limit}-byte limit"
    TextMalformedChunk(kind, offset) =>
      "malformed \{kind} text chunk at byte \{offset}"
    TextInvalidKeyword(position) =>
      "invalid PNG text keyword at entry or byte \{position}"
    TextInvalidLatin1(field) =>
      "\{field} contains characters outside PNG Latin-1 text"
    TextInvalidUtf8(field) => "\{field} is not valid null-free UTF-8"
    TextInvalidLanguageTag(position) =>
      "invalid iTXt language tag at entry or byte \{position}"
    TextUnexpectedInternationalFields(position) =>
      "Latin-1 text entry \{position} cannot contain international fields"
    TextInvalidCompressionFlag(flag, offset) =>
      "invalid iTXt compression flag \{flag.to_uint()} at byte \{offset}"
    TextUnsupportedCompression(kind, method_value, offset) =>
      "unsupported \{kind} compression method \{method_value.to_uint()} at byte \{offset}"
    TextDecompressionFailed(kind, offset, error) =>
      "cannot decompress \{kind} chunk at byte \{offset}: \{error.message()}"
    TextOutputTooLarge => "PNG text update would exceed the supported size"
  }
}
