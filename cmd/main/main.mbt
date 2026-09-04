///|
fn demo_png() -> Bytes {
  b"\x89PNG\r\n\x1a\n" +
  b"\x00\x00\x00\x0dIHDR" +
  b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00" +
  b"\x1f\x15\xc4\x89" +
  b"\x00\x00\x00\x00IDAT\x35\xaf\x06\x1e" +
  b"\x00\x00\x00\x00IEND\xae\x42\x60\x82"
}

///|
fn main {
  println("MoonPNG structural inspection demo")
  match @moonpng.inspect(demo_png()) {
    Err(error) => println("error: \{error.message()}")
    Ok(info) => {
      println(
        "image: \{info.width}x\{info.height}, bit_depth=\{info.bit_depth.to_uint()}, color_type=\{info.color_type.to_uint()}",
      )
      println("chunks: \{info.chunks.length()}")
      for chunk in info.chunks {
        println(
          "- \{chunk.kind} offset=\{chunk.offset} length=\{chunk.length} crc=ok critical=\{chunk.is_critical}",
        )
      }
    }
  }
}
