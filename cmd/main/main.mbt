///|
fn demo_png() -> Bytes {
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
fn main {
  println("MoonPNG decode demo")
  match @moonpng.decode(demo_png()) {
    Err(error) => println("error: \{error.message()}")
    Ok(image) => {
      println("image: \{image.width}x\{image.height}, format=RGBA8")
      match image.pixel_at(0, 0) {
        Some(pixel) =>
          println(
            "pixel(0, 0): rgba(\{pixel.red.to_uint()}, \{pixel.green.to_uint()}, \{pixel.blue.to_uint()}, \{pixel.alpha.to_uint()})",
          )
        None => println("pixel not found")
      }
    }
  }
}
