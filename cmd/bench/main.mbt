///|
fn make_solid(width : Int, height : Int) -> Bytes {
  let pixels = Array::make(width * height * 4, b'\x00')
  for offset = 0; offset < pixels.length(); offset = offset + 4 {
    pixels[offset] = b'\x28'
    pixels[offset + 1] = b'\x78'
    pixels[offset + 2] = b'\xc8'
    pixels[offset + 3] = b'\xff'
  }
  Bytes::from_array(pixels)
}

///|
fn make_gradient(width : Int, height : Int) -> Bytes {
  let pixels = Array::make(width * height * 4, b'\x00')
  for y = 0; y < height; y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      let offset = (y * width + x) * 4
      pixels[offset] = (x * 255 / (width - 1)).to_byte()
      pixels[offset + 1] = (y * 255 / (height - 1)).to_byte()
      pixels[offset + 2] = ((x + y) * 255 / (width + height - 2)).to_byte()
      pixels[offset + 3] = b'\xff'
    }
  }
  Bytes::from_array(pixels)
}

///|
fn make_tiles(width : Int, height : Int) -> Bytes {
  let pixels = Array::make(width * height * 4, b'\x00')
  for y = 0; y < height; y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      let offset = (y * width + x) * 4
      let tile = (x / 8 + y / 8) % 4
      pixels[offset] = (tile * 70 + 25).to_byte()
      pixels[offset + 1] = ((3 - tile) * 65 + 30).to_byte()
      pixels[offset + 2] = (tile * 45 + 55).to_byte()
      pixels[offset + 3] = b'\xff'
    }
  }
  Bytes::from_array(pixels)
}

///|
fn make_noise(width : Int, height : Int) -> Bytes {
  let pixels = Array::make(width * height * 4, b'\x00')
  let mut state = 1729
  for offset = 0; offset < pixels.length(); offset = offset + 4 {
    state = (state * 251 + 137) % 65521
    pixels[offset] = (state % 256).to_byte()
    state = (state * 251 + 137) % 65521
    pixels[offset + 1] = (state % 256).to_byte()
    state = (state * 251 + 137) % 65521
    pixels[offset + 2] = (state % 256).to_byte()
    pixels[offset + 3] = b'\xff'
  }
  Bytes::from_array(pixels)
}

///|
fn encode_sample(
  width : Int,
  height : Int,
  pixels : Bytes,
  strategy : @moonpng.CompressionStrategy,
) -> Bytes {
  let options : @moonpng.EncodeOptions = {
    filter_strategy: @moonpng.FilterAdaptive,
    compression_strategy: strategy,
  }
  match
    @moonpng.encode_rgba8_with_options(
      width.reinterpret_as_uint(),
      height.reinterpret_as_uint(),
      pixels,
      options,
    ) {
    Ok(png) => png
    Err(error) => abort("encode failed: " + error.message())
  }
}

///|
fn verify_round_trip(png : Bytes, pixels : Bytes) -> Unit {
  match @moonpng.decode(png) {
    Ok(image) =>
      if image.pixels != pixels {
        abort("decoded pixels differ from the benchmark source")
      }
    Err(error) => abort("decode failed: " + error.message())
  }
}

///|
fn percent_of_raw(encoded_size : Int, raw_size : Int) -> String {
  let tenths = (encoded_size * 1000 + raw_size / 2) / raw_size
  "\{tenths / 10}.\{tenths % 10}%"
}

///|
fn run_sample(name : String, width : Int, height : Int, pixels : Bytes) -> Unit {
  let stored = encode_sample(width, height, pixels, @moonpng.CompressionStored)
  let fixed = encode_sample(width, height, pixels, @moonpng.CompressionFixed)
  let automatic = encode_sample(width, height, pixels, @moonpng.CompressionAuto)
  verify_round_trip(stored, pixels)
  verify_round_trip(fixed, pixels)
  verify_round_trip(automatic, pixels)
  let (expected, selected) = if fixed.length() < stored.length() {
    (fixed, "fixed")
  } else {
    (stored, "stored")
  }
  if automatic != expected {
    abort("automatic compression did not select the shortest output")
  }
  println(
    "\{name}\t\{pixels.length()}\t\{stored.length()}\t\{fixed.length()}\t\{automatic.length()}\t\{percent_of_raw(automatic.length(), pixels.length())}\t\{selected}",
  )
}

///|
fn main {
  let width = 128
  let height = 128
  println("MoonPNG deterministic compression benchmark")
  println("All outputs are decoded and checked byte-for-byte before reporting.")
  println("sample\traw\tstored\tfixed\tauto\tauto/raw\tselected")
  run_sample("solid", width, height, make_solid(width, height))
  run_sample("gradient", width, height, make_gradient(width, height))
  run_sample("tiles", width, height, make_tiles(width, height))
  run_sample("noise", width, height, make_noise(width, height))
}
