///|
fn text_copy_range(data : Bytes, start : Int, length : Int) -> Bytes {
  let output : Array[Byte] = []
  output.reserve_capacity(length)
  for index = 0; index < length; index = index + 1 {
    output.push(data.unsafe_get(start + index))
  }
  Bytes::from_array(output)
}

///|
fn text_append_range(
  output : Array[Byte],
  data : Bytes,
  start : Int,
  length : Int,
) -> Unit {
  for index = 0; index < length; index = index + 1 {
    output.push(data.unsafe_get(start + index))
  }
}

///|
fn text_find_zero(data : Bytes, start : Int, end : Int) -> Int {
  for index = start; index < end; index = index + 1 {
    if data.unsafe_get(index) == b'\x00' {
      return index
    }
  }
  -1
}

///|
fn text_contains_zero(data : Bytes) -> Bool {
  for byte in data {
    if byte == b'\x00' {
      return true
    }
  }
  false
}

///|
fn text_keyword_is_valid(data : Bytes) -> Bool {
  if data.length() < 1 || data.length() > 79 {
    return false
  }
  let mut previous_space = false
  for index, byte in data {
    let value = byte.to_int()
    let valid = (value >= 32 && value <= 126) || (value >= 161 && value <= 255)
    if !valid {
      return false
    }
    let is_space = value == 32
    if (index == 0 || index + 1 == data.length() || previous_space) && is_space {
      return false
    }
    previous_space = is_space
  }
  true
}

///|
fn text_latin1_is_valid(data : Bytes) -> Bool {
  for byte in data {
    let value = byte.to_int()
    if value != 10 &&
      !(value >= 32 && value <= 126) &&
      !(value >= 161 && value <= 255) {
      return false
    }
  }
  true
}

///|
fn text_ascii_letter(byte : Byte) -> Bool {
  let value = byte.to_int()
  (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
}

///|
fn text_ascii_alphanumeric(byte : Byte) -> Bool {
  let value = byte.to_int()
  text_ascii_letter(byte) || (value >= 48 && value <= 57)
}

///|
fn text_language_tag_is_valid(data : Bytes) -> Bool {
  if data.length() == 0 {
    return true
  }
  let mut subtag_start = 0
  let mut subtag_length = 0
  let mut first = true
  for index, byte in data {
    if byte == b'-' {
      if subtag_length == 0 || subtag_length > 8 {
        return false
      }
      if first {
        if subtag_length == 1 {
          let first_byte = data.unsafe_get(subtag_start)
          if first_byte != b'x' &&
            first_byte != b'X' &&
            first_byte != b'i' &&
            first_byte != b'I' {
            return false
          }
        }
        for first_index = subtag_start
            first_index < index
            first_index = first_index + 1 {
          if !text_ascii_letter(data.unsafe_get(first_index)) {
            return false
          }
        }
      }
      first = false
      subtag_start = index + 1
      subtag_length = 0
    } else {
      if !text_ascii_alphanumeric(byte) {
        return false
      }
      subtag_length = subtag_length + 1
    }
  }
  if subtag_length == 0 || subtag_length > 8 {
    return false
  }
  if first {
    if subtag_length == 1 {
      return false
    }
    for byte in data {
      if !text_ascii_letter(byte) {
        return false
      }
    }
  }
  true
}

///|
fn text_decode_latin1(data : Bytes) -> String {
  let builder = StringBuilder(size_hint=data.length())
  for byte in data {
    builder.write_char(byte.to_char())
  }
  builder.to_string()
}

///|
fn text_encode_latin1(
  value : String,
  field : String,
) -> Result[Bytes, TextError] {
  let output : Array[Byte] = []
  for char in value {
    let code = char.to_int()
    if code < 0 || code > 255 {
      return Err(TextInvalidLatin1(field))
    }
    output.push(code.to_byte())
  }
  let bytes = Bytes::from_array(output)
  if !text_latin1_is_valid(bytes) {
    return Err(TextInvalidLatin1(field))
  }
  Ok(bytes)
}

///|
fn text_decode_utf8(data : Bytes, field : String) -> Result[String, TextError] {
  if text_contains_zero(data) {
    return Err(TextInvalidUtf8(field))
  }
  Ok(@utf8.decode(data)) catch {
    _ => Err(TextInvalidUtf8(field))
  }
}

///|
fn text_decompress(
  kind : String,
  offset : Int,
  compressed : Bytes,
  limit : Int,
) -> Result[Bytes, TextError] {
  match inflate_zlib_with_limit(compressed, max_output_size=limit) {
    Ok(output) => Ok(output)
    Err(OutputLimitExceeded(_)) => Err(TextDecodedDataTooLarge(limit))
    Err(error) => Err(TextDecompressionFailed(kind, offset, error))
  }
}

///|
fn text_parse_keyword(
  data : Bytes,
  start : Int,
  separator : Int,
  position : Int,
) -> Result[String, TextError] {
  let keyword_bytes = text_copy_range(data, start, separator - start)
  if !text_keyword_is_valid(keyword_bytes) {
    return Err(TextInvalidKeyword(position))
  }
  Ok(text_decode_latin1(keyword_bytes))
}

///|
fn text_parse_latin1_chunk(
  data : Bytes,
  chunk : ChunkInfo,
  compressed : Bool,
  decoded_limit : Int,
) -> Result[(TextEntry, Int), TextError] {
  let start = chunk.data_offset
  let end = start + chunk.length
  let separator = text_find_zero(data, start, end)
  if separator < 0 || separator + 1 > end {
    return Err(TextMalformedChunk(chunk.kind, chunk.offset))
  }
  let keyword = match text_parse_keyword(data, start, separator, chunk.offset) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let text_bytes = if compressed {
    if separator + 2 > end {
      return Err(TextMalformedChunk(chunk.kind, chunk.offset))
    }
    let method_value = data.unsafe_get(separator + 1)
    if method_value != b'\x00' {
      return Err(
        TextUnsupportedCompression(chunk.kind, method_value, chunk.offset),
      )
    }
    let compressed_text = text_copy_range(
      data,
      separator + 2,
      end - separator - 2,
    )
    match
      text_decompress(chunk.kind, chunk.offset, compressed_text, decoded_limit) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  } else {
    text_copy_range(data, separator + 1, end - separator - 1)
  }
  if text_bytes.length() > decoded_limit {
    return Err(TextDecodedDataTooLarge(decoded_limit))
  }
  if !text_latin1_is_valid(text_bytes) {
    return Err(TextInvalidLatin1("text"))
  }
  Ok(
    (
      {
        format: if compressed {
          TextLatin1Compressed
        } else {
          TextLatin1
        },
        keyword,
        text: text_decode_latin1(text_bytes),
        language_tag: "",
        translated_keyword: "",
      },
      text_bytes.length(),
    ),
  )
}

///|
fn text_parse_international_chunk(
  data : Bytes,
  chunk : ChunkInfo,
  decoded_limit : Int,
) -> Result[(TextEntry, Int), TextError] {
  let start = chunk.data_offset
  let end = start + chunk.length
  let keyword_end = text_find_zero(data, start, end)
  if keyword_end < 0 || keyword_end + 3 > end {
    return Err(TextMalformedChunk(chunk.kind, chunk.offset))
  }
  let keyword = match
    text_parse_keyword(data, start, keyword_end, chunk.offset) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let flag = data.unsafe_get(keyword_end + 1)
  if flag != b'\x00' && flag != b'\x01' {
    return Err(TextInvalidCompressionFlag(flag, chunk.offset))
  }
  let method_value = data.unsafe_get(keyword_end + 2)
  if flag == b'\x01' && method_value != b'\x00' {
    return Err(
      TextUnsupportedCompression(chunk.kind, method_value, chunk.offset),
    )
  }
  let language_start = keyword_end + 3
  let language_end = text_find_zero(data, language_start, end)
  if language_end < 0 {
    return Err(TextMalformedChunk(chunk.kind, chunk.offset))
  }
  let translated_start = language_end + 1
  let translated_end = text_find_zero(data, translated_start, end)
  if translated_end < 0 {
    return Err(TextMalformedChunk(chunk.kind, chunk.offset))
  }
  let language_bytes = text_copy_range(
    data,
    language_start,
    language_end - language_start,
  )
  if !text_language_tag_is_valid(language_bytes) {
    return Err(TextInvalidLanguageTag(chunk.offset))
  }
  let language_tag = text_decode_latin1(language_bytes)
  let translated_bytes = text_copy_range(
    data,
    translated_start,
    translated_end - translated_start,
  )
  let translated_keyword = match
    text_decode_utf8(translated_bytes, "translated keyword") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let stored_text = text_copy_range(
    data,
    translated_end + 1,
    end - translated_end - 1,
  )
  let text_bytes = if flag == b'\x01' {
    match
      text_decompress(chunk.kind, chunk.offset, stored_text, decoded_limit) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  } else {
    stored_text
  }
  let decoded_size = language_bytes.length() +
    translated_bytes.length() +
    text_bytes.length()
  if decoded_size > decoded_limit {
    return Err(TextDecodedDataTooLarge(decoded_limit))
  }
  let text = match text_decode_utf8(text_bytes, "international text") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(
    (
      {
        format: if flag == b'\x01' {
          TextInternationalCompressed
        } else {
          TextInternational
        },
        keyword,
        text,
        language_tag,
        translated_keyword,
      },
      decoded_size,
    ),
  )
}

///|
/// Read PNG text chunks using caller-provided aggregate resource limits.
pub fn read_text_entries_with_limits(
  data : Bytes,
  limits : TextLimits,
) -> Result[Array[TextEntry], TextError] {
  if limits.max_entries <= 0 ||
    limits.max_encoded_bytes <= 0 ||
    limits.max_decoded_bytes <= 0 {
    return Err(TextInvalidLimits)
  }
  let info = match inspect(data) {
    Ok(value) => value
    Err(error) => return Err(TextInvalidContainer(error))
  }
  let entries : Array[TextEntry] = []
  let mut encoded_total = 0
  let mut decoded_total = 0
  for chunk in info.chunks {
    if chunk.kind != "tEXt" && chunk.kind != "zTXt" && chunk.kind != "iTXt" {
      continue
    }
    if entries.length() >= limits.max_entries {
      return Err(TextTooManyEntries(limits.max_entries))
    }
    if chunk.length > limits.max_encoded_bytes - encoded_total {
      return Err(TextEncodedDataTooLarge(limits.max_encoded_bytes))
    }
    encoded_total = encoded_total + chunk.length
    let remaining = limits.max_decoded_bytes - decoded_total
    let parsed = if chunk.kind == "tEXt" {
      text_parse_latin1_chunk(data, chunk, false, remaining)
    } else if chunk.kind == "zTXt" {
      text_parse_latin1_chunk(data, chunk, true, remaining)
    } else {
      text_parse_international_chunk(data, chunk, remaining)
    }
    match parsed {
      Err(TextDecodedDataTooLarge(_)) =>
        return Err(TextDecodedDataTooLarge(limits.max_decoded_bytes))
      Err(error) => return Err(error)
      Ok((entry, decoded_size)) => {
        if decoded_size > remaining {
          return Err(TextDecodedDataTooLarge(limits.max_decoded_bytes))
        }
        entries.push(entry)
        decoded_total = decoded_total + decoded_size
      }
    }
  }
  Ok(entries)
}

///|
/// Read all tEXt, zTXt, and iTXt entries from a validated PNG.
pub fn read_text_entries(data : Bytes) -> Result[Array[TextEntry], TextError] {
  read_text_entries_with_limits(data, default_text_limits())
}

///|
fn text_encode_keyword(
  keyword : String,
  position : Int,
) -> Result[Bytes, TextError] {
  let output : Array[Byte] = []
  for char in keyword {
    let code = char.to_int()
    if code < 0 || code > 255 {
      return Err(TextInvalidKeyword(position))
    }
    output.push(code.to_byte())
  }
  let bytes = Bytes::from_array(output)
  if !text_keyword_is_valid(bytes) {
    return Err(TextInvalidKeyword(position))
  }
  Ok(bytes)
}

///|
fn text_make_chunk(kind : Bytes, payload : Array[Byte]) -> Bytes {
  let output : Array[Byte] = []
  encode_append_chunk(output, kind, Bytes::from_array(payload))
  Bytes::from_array(output)
}

///|
fn text_serialize_entry(
  entry : TextEntry,
  position : Int,
) -> Result[(Bytes, Int, Int), TextError] {
  let keyword = match text_encode_keyword(entry.keyword, position) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let payload : Array[Byte] = []
  encode_append_bytes(payload, keyword)
  payload.push(b'\x00')
  match entry.format {
    TextLatin1 | TextLatin1Compressed => {
      if entry.language_tag != "" || entry.translated_keyword != "" {
        return Err(TextUnexpectedInternationalFields(position))
      }
      let text = match text_encode_latin1(entry.text, "text") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if entry.format == TextLatin1Compressed {
        payload.push(b'\x00')
        encode_append_bytes(payload, compress_zlib(text, CompressionAuto))
        let chunk = text_make_chunk(b"zTXt", payload)
        return Ok((chunk, payload.length(), text.length()))
      }
      encode_append_bytes(payload, text)
      let chunk = text_make_chunk(b"tEXt", payload)
      Ok((chunk, payload.length(), text.length()))
    }
    TextInternational | TextInternationalCompressed => {
      let language = @utf8.encode(entry.language_tag)
      if !text_language_tag_is_valid(language) {
        return Err(TextInvalidLanguageTag(position))
      }
      let translated = @utf8.encode(entry.translated_keyword)
      if text_contains_zero(translated) {
        return Err(TextInvalidUtf8("translated keyword"))
      }
      let text = @utf8.encode(entry.text)
      if text_contains_zero(text) {
        return Err(TextInvalidUtf8("international text"))
      }
      let compressed = entry.format == TextInternationalCompressed
      payload.push(if compressed { b'\x01' } else { b'\x00' })
      payload.push(b'\x00')
      encode_append_bytes(payload, language)
      payload.push(b'\x00')
      encode_append_bytes(payload, translated)
      payload.push(b'\x00')
      if compressed {
        encode_append_bytes(payload, compress_zlib(text, CompressionAuto))
      } else {
        encode_append_bytes(payload, text)
      }
      let chunk = text_make_chunk(b"iTXt", payload)
      Ok(
        (
          chunk,
          payload.length(),
          language.length() + translated.length() + text.length(),
        ),
      )
    }
  }
}

///|
fn text_is_chunk(kind : String) -> Bool {
  kind == "tEXt" || kind == "zTXt" || kind == "iTXt"
}

///|
fn text_update_entries(
  data : Bytes,
  entries : Array[TextEntry],
  replace : Bool,
) -> Result[Bytes, TextError] {
  let limits = default_text_limits()
  if entries.length() > limits.max_entries {
    return Err(TextTooManyEntries(limits.max_entries))
  }
  let info = match inspect(data) {
    Ok(value) => value
    Err(error) => return Err(TextInvalidContainer(error))
  }
  let chunks : Array[Bytes] = []
  let mut encoded_total = 0
  let mut decoded_total = 0
  let mut added_size = 0
  for index, entry in entries {
    match text_serialize_entry(entry, index) {
      Err(error) => return Err(error)
      Ok((chunk, encoded_size, decoded_size)) => {
        if encoded_size > limits.max_encoded_bytes - encoded_total {
          return Err(TextEncodedDataTooLarge(limits.max_encoded_bytes))
        }
        if decoded_size > limits.max_decoded_bytes - decoded_total {
          return Err(TextDecodedDataTooLarge(limits.max_decoded_bytes))
        }
        if chunk.length() > 0x7fffffff - added_size {
          return Err(TextOutputTooLarge)
        }
        encoded_total = encoded_total + encoded_size
        decoded_total = decoded_total + decoded_size
        added_size = added_size + chunk.length()
        chunks.push(chunk)
      }
    }
  }
  let mut removed_size = 0
  if replace {
    for chunk in info.chunks {
      if text_is_chunk(chunk.kind) {
        removed_size = removed_size + chunk.length + 12
      }
    }
  }
  let retained_size = data.length() - removed_size
  if added_size > 0x7fffffff - retained_size {
    return Err(TextOutputTooLarge)
  }
  let output : Array[Byte] = []
  output.reserve_capacity(retained_size + added_size)
  text_append_range(output, data, 0, 8)
  let mut inserted = false
  for chunk in info.chunks {
    if !inserted && chunk.kind == "IDAT" {
      for text_chunk in chunks {
        encode_append_bytes(output, text_chunk)
      }
      inserted = true
    }
    if !replace || !text_is_chunk(chunk.kind) {
      text_append_range(output, data, chunk.offset, chunk.length + 12)
    }
  }
  Ok(Bytes::from_array(output))
}

///|
/// Insert text entries before image data while preserving existing chunks.
pub fn add_text_entries(
  data : Bytes,
  entries : Array[TextEntry],
) -> Result[Bytes, TextError] {
  text_update_entries(data, entries, false)
}

///|
/// Replace all tEXt, zTXt, and iTXt chunks while preserving image data and
/// every unrelated chunk byte-for-byte.
pub fn replace_text_entries(
  data : Bytes,
  entries : Array[TextEntry],
) -> Result[Bytes, TextError] {
  text_update_entries(data, entries, true)
}
