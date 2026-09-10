///|
fn guard_fixture() -> Bytes {
  b"\x89PNG\r\n\x1a\n" +
  b"\x00\x00\x00\x0dIHDR" +
  b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00" +
  b"\x1f\x15\xc4\x89" +
  b"\x00\x00\x00\x0dIDAT" +
  b"\x78\xda\x63\xf8\xcf\xc0\xf0\x1f\x00\x05\x00\x01\xff" +
  b"\x56\xc7\x2f\x0d" +
  b"\x00\x00\x00\x00IEND\xae\x42\x60\x82"
}

///|
test "guard accepts a completely decoded PNG" {
  match evaluate_png(guard_fixture()) {
    Rejected(stage, message) =>
      fail("unexpected rejection at \{stage}: \{message}")
    Accepted(summary) => {
      inspect(summary.width, content="1")
      inspect(summary.height, content="1")
      inspect(summary.chunk_count, content="3")
      inspect(summary.idat_bytes, content="13")
      inspect(summary.decoded_bytes, content="4")
      inspect(summary.text_entries, content="0")
    }
  }
}

///|
test "guard reports the failing validation stage" {
  match evaluate_png(b"not a PNG") {
    Accepted(_) => fail("invalid data was accepted")
    Rejected(stage, message) => {
      inspect(stage, content="container")
      inspect(message.length() > 0, content="true")
    }
  }
}

///|
test "guard enforces caller-provided inflated byte budgets" {
  let defaults = default_guard_policy()
  let policy : GuardPolicy = {
    ..defaults,
    decode_limits: { ..defaults.decode_limits, max_inflated_size: 1, },
  }
  match evaluate_png_with_policy(guard_fixture(), policy) {
    Accepted(_) => fail("PNG exceeding the inflated byte budget was accepted")
    Rejected(stage, message) => {
      inspect(stage, content="decode")
      inspect(message.contains("inflated data"), content="true")
    }
  }
}

///|
test "guard enforces caller-provided chunk budgets" {
  let defaults = default_guard_policy()
  let policy : GuardPolicy = {
    ..defaults,
    decode_limits: { ..defaults.decode_limits, max_chunks: 2, },
  }
  match evaluate_png_with_policy(guard_fixture(), policy) {
    Accepted(_) => fail("PNG exceeding the chunk budget was accepted")
    Rejected(stage, message) => {
      inspect(stage, content="container")
      inspect(message.contains("chunk"), content="true")
    }
  }
}

///|
test "guard enforces caller-provided text entry budgets" {
  let with_text = match
    @moonpng.add_text_entries(guard_fixture(), [
      @moonpng.latin1_text("Author", "one"),
      @moonpng.latin1_text("Comment", "two"),
    ]) {
    Ok(png) => png
    Err(error) => fail(error.message())
  }
  let defaults = default_guard_policy()
  let policy : GuardPolicy = {
    ..defaults,
    text_limits: { ..defaults.text_limits, max_entries: 1, },
  }
  match evaluate_png_with_policy(with_text, policy) {
    Accepted(_) => fail("PNG exceeding the text entry budget was accepted")
    Rejected(stage, message) => {
      inspect(stage, content="metadata")
      inspect(message.contains("text entries"), content="true")
    }
  }
}
