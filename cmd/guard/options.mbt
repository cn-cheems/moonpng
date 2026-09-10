///|
pub(all) struct GuardCliOptions {
  policy : GuardPolicy
  files : Array[String]
}

///|
pub(all) enum GuardCliParse {
  GuardCliReady(GuardCliOptions)
  GuardCliHelp
  GuardCliError(String)
}

///|
pub fn guard_usage() -> String {
  "Usage: moon run cmd/guard --target js -- [OPTIONS] <file.png> [more.png ...]\n" +
  "Options:\n" +
  "  --max-chunk-size N          Maximum bytes in one PNG chunk\n" +
  "  --max-chunks N              Maximum PNG chunk count\n" +
  "  --max-compressed-size N     Maximum combined IDAT bytes\n" +
  "  --max-inflated-size N       Maximum inflated scanline bytes\n" +
  "  --max-pixels N              Maximum decoded pixel count\n" +
  "  --max-text-entries N        Maximum textual chunk count\n" +
  "  --max-text-encoded-size N   Maximum encoded text bytes\n" +
  "  --max-text-decoded-size N   Maximum decoded text bytes\n" +
  "  --help                      Show this help"
}

///|
fn parse_positive_limit(flag : String, text : String) -> Result[Int, String] {
  let parsed : Int? = Some(@string.parse_int(text)) catch { _ => None }
  match parsed {
    Some(value) if value > 0 => Ok(value)
    _ => Err("\{flag} expects a positive integer, received '\{text}'")
  }
}

///|
fn is_limit_flag(flag : String) -> Bool {
  match flag {
    "--max-chunk-size"
    | "--max-chunks"
    | "--max-compressed-size"
    | "--max-inflated-size"
    | "--max-pixels"
    | "--max-text-entries"
    | "--max-text-encoded-size"
    | "--max-text-decoded-size" => true
    _ => false
  }
}

///|
fn guard_policy_with_limit(
  policy : GuardPolicy,
  flag : String,
  value : Int,
) -> GuardPolicy {
  match flag {
    "--max-chunk-size" =>
      {
        ..policy,
        decode_limits: { ..policy.decode_limits, max_chunk_size: value, },
      }
    "--max-chunks" =>
      {
        ..policy,
        decode_limits: { ..policy.decode_limits, max_chunks: value, },
      }
    "--max-compressed-size" =>
      {
        ..policy,
        decode_limits: { ..policy.decode_limits, max_compressed_size: value, },
      }
    "--max-inflated-size" =>
      {
        ..policy,
        decode_limits: { ..policy.decode_limits, max_inflated_size: value, },
      }
    "--max-pixels" =>
      {
        ..policy,
        decode_limits: { ..policy.decode_limits, max_pixels: value, },
      }
    "--max-text-entries" =>
      { ..policy, text_limits: { ..policy.text_limits, max_entries: value, }, }
    "--max-text-encoded-size" =>
      {
        ..policy,
        text_limits: { ..policy.text_limits, max_encoded_bytes: value, },
      }
    "--max-text-decoded-size" =>
      {
        ..policy,
        text_limits: { ..policy.text_limits, max_decoded_bytes: value, },
      }
    _ => policy
  }
}

///|
pub fn parse_guard_cli(args : Array[String]) -> GuardCliParse {
  let mut policy = default_guard_policy()
  let files : Array[String] = []
  let mut index = 0
  let mut positional_only = false
  while index < args.length() {
    let argument = args[index]
    if positional_only {
      files.push(argument)
      index = index + 1
    } else if argument == "--help" {
      return GuardCliHelp
    } else if argument == "--" {
      positional_only = true
      index = index + 1
    } else if is_limit_flag(argument) {
      if index + 1 >= args.length() {
        return GuardCliError("missing value for \{argument}")
      }
      let value = match parse_positive_limit(argument, args[index + 1]) {
        Ok(value) => value
        Err(message) => return GuardCliError(message)
      }
      policy = guard_policy_with_limit(policy, argument, value)
      index = index + 2
    } else if argument.has_prefix("--") {
      return GuardCliError("unknown option '\{argument}'")
    } else {
      files.push(argument)
      index = index + 1
    }
  }
  if files.length() == 0 {
    GuardCliError("at least one PNG file is required")
  } else {
    GuardCliReady({ policy, files, })
  }
}
