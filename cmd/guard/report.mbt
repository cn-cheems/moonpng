///|
pub(all) struct GuardSummary {
  width : UInt
  height : UInt
  bit_depth : Byte
  color_type : Byte
  interlace_method : Byte
  chunk_count : Int
  idat_bytes : Int
  decoded_bytes : Int
  text_entries : Int
}

///|
pub(all) enum GuardCheck {
  Accepted(GuardSummary)
  Rejected(String, String)
}

///|
pub(all) struct GuardPolicy {
  decode_limits : @moonpng.DecodeLimits
  text_limits : @moonpng.TextLimits
}

///|
pub fn default_guard_policy() -> GuardPolicy {
  {
    decode_limits: @moonpng.default_decode_limits(),
    text_limits: @moonpng.default_text_limits(),
  }
}

///|
pub fn evaluate_png_with_policy(
  data : Bytes,
  policy : GuardPolicy,
) -> GuardCheck {
  let info = match
    @moonpng.inspect_with_limits(
      data,
      max_chunk_size=policy.decode_limits.max_chunk_size,
      max_chunks=policy.decode_limits.max_chunks,
    ) {
    Err(error) => return Rejected("container", error.message())
    Ok(info) => info
  }
  let text_entries = match
    @moonpng.read_text_entries_with_limits(data, policy.text_limits) {
    Err(error) => return Rejected("metadata", error.message())
    Ok(entries) => entries.length()
  }
  let image = match @moonpng.decode_with_limits(data, policy.decode_limits) {
    Err(error) => return Rejected("decode", error.message())
    Ok(image) => image
  }
  let mut idat_bytes = 0
  for chunk in info.chunks {
    if chunk.kind == "IDAT" {
      idat_bytes += chunk.length
    }
  }
  Accepted({
    width: info.width,
    height: info.height,
    bit_depth: info.bit_depth,
    color_type: info.color_type,
    interlace_method: info.interlace_method,
    chunk_count: info.chunks.length(),
    idat_bytes,
    decoded_bytes: image.pixels.length(),
    text_entries,
  })
}

///|
pub fn evaluate_png(data : Bytes) -> GuardCheck {
  evaluate_png_with_policy(data, default_guard_policy())
}
