///|
extern "js" fn node_read_file(path : String) -> Bytes =
  #| function(path) {
  #|   try {
  #|     globalThis.__moonpngGuardReadError = "";
  #|     const fs = require("node:fs");
  #|     return new Uint8Array(fs.readFileSync(path));
  #|   } catch (error) {
  #|     globalThis.__moonpngGuardReadError = error instanceof Error
  #|       ? error.message
  #|       : String(error);
  #|     return new Uint8Array();
  #|   }
  #| }

///|
extern "js" fn node_last_read_error() -> String =
  #| function() {
  #|   return globalThis.__moonpngGuardReadError || "";
  #| }

///|
extern "js" fn emit_accepted(path : String, summary : GuardSummary) -> Unit =
  #| function(path, summary) {
  #|   console.log(JSON.stringify({
  #|     path,
  #|     status: "accepted",
  #|     width: summary.width,
  #|     height: summary.height,
  #|     bit_depth: summary.bit_depth,
  #|     color_type: summary.color_type,
  #|     interlace_method: summary.interlace_method,
  #|     chunk_count: summary.chunk_count,
  #|     idat_bytes: summary.idat_bytes,
  #|     decoded_bytes: summary.decoded_bytes,
  #|     text_entries: summary.text_entries,
  #|   }));
  #| }

///|
extern "js" fn emit_rejected(
  path : String,
  stage : String,
  message : String,
) -> Unit =
  #| function(path, stage, message) {
  #|   console.log(JSON.stringify({ path, status: "rejected", stage, message }));
  #| }

///|
extern "js" fn node_set_exit_code(code : Int) -> Unit =
  #| function(code) {
  #|   process.exitCode = code;
  #| }

///|
fn main {
  let args = @env.args()
  if args.length() <= 2 {
    println(
      "Usage: moon run cmd/guard --target js -- <file.png> [more.png ...]",
    )
    node_set_exit_code(2)
    return
  }
  let mut exit_code = 0
  for index = 2; index < args.length(); index = index + 1 {
    let path = args[index]
    let data = node_read_file(path)
    let read_error = node_last_read_error()
    if read_error != "" {
      emit_rejected(path, "read", read_error)
      exit_code = 2
    } else {
      match evaluate_png(data) {
        Accepted(summary) => emit_accepted(path, summary)
        Rejected(stage, message) => {
          emit_rejected(path, stage, message)
          if exit_code == 0 {
            exit_code = 1
          }
        }
      }
    }
  }
  node_set_exit_code(exit_code)
}
