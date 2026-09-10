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
