///|
test "guard CLI parses independent resource limits" {
  match
    parse_guard_cli([
      "--max-chunk-size", "101", "--max-chunks", "102", "--max-compressed-size",
      "103", "--max-inflated-size", "104", "--max-pixels", "105", "--max-text-entries",
      "106", "--max-text-encoded-size", "107", "--max-text-decoded-size", "108",
      "one.png", "two.png",
    ]) {
    GuardCliReady(options) => {
      inspect(options.policy.decode_limits.max_chunk_size, content="101")
      inspect(options.policy.decode_limits.max_chunks, content="102")
      inspect(options.policy.decode_limits.max_compressed_size, content="103")
      inspect(options.policy.decode_limits.max_inflated_size, content="104")
      inspect(options.policy.decode_limits.max_pixels, content="105")
      inspect(options.policy.text_limits.max_entries, content="106")
      inspect(options.policy.text_limits.max_encoded_bytes, content="107")
      inspect(options.policy.text_limits.max_decoded_bytes, content="108")
      inspect(options.files.length(), content="2")
      inspect(options.files[0], content="one.png")
      inspect(options.files[1], content="two.png")
    }
    GuardCliHelp => fail("unexpected help")
    GuardCliError(message) => fail(message)
  }
}

///|
test "guard CLI rejects missing, invalid, and unknown options" {
  let cases = [
    (["--max-pixels"], "missing value"),
    (["--max-pixels", "0", "image.png"], "positive integer"),
    (["--max-pixels", "many", "image.png"], "positive integer"),
    (["--unknown", "image.png"], "unknown option"),
    ([], "at least one PNG file"),
  ]
  for (args, expected) in cases {
    match parse_guard_cli(args) {
      GuardCliError(message) =>
        inspect(message.contains(expected), content="true")
      GuardCliReady(_) => fail("invalid arguments were accepted")
      GuardCliHelp => fail("invalid arguments displayed help")
    }
  }
}

///|
test "guard CLI supports option terminator" {
  match parse_guard_cli(["--", "--fixture.png"]) {
    GuardCliReady(options) => {
      inspect(options.files.length(), content="1")
      inspect(options.files[0], content="--fixture.png")
    }
    GuardCliHelp => fail("unexpected help")
    GuardCliError(message) => fail(message)
  }
}
