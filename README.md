# MoonPNG

MoonPNG is a pure MoonBit PNG parser and decoder. It validates the PNG
container, inflates zlib/DEFLATE image data, reverses PNG scanline filters, and
returns portable RGBA8 pixels without FFI or platform-specific dependencies.

Repository: <https://github.com/cn-cheems/moonpng>

## Current capabilities

- validates the PNG signature, chunk bounds, names, ordering, and CRC-32;
- applies resource limits to chunk count, compressed data, inflated data, and
  pixel count;
- implements zlib header and Adler-32 validation;
- inflates stored, fixed-Huffman, and dynamic-Huffman DEFLATE blocks;
- rejects malformed Huffman trees, invalid back-references, truncated input,
  output-limit violations, and trailing compressed bytes;
- reverses all five PNG scanline filters: None, Sub, Up, Average, and Paeth;
- decodes non-interlaced color types 0, 2, 3, 4, and 6;
- expands 1-, 2-, and 4-bit packed grayscale and indexed-color samples;
- validates and expands `PLTE` palettes;
- supports `tRNS` transparency for grayscale, truecolor, and indexed images;
- converts decoded output to row-major RGBA8;
- runs on MoonBit's native, JavaScript, Wasm, and Wasm GC targets.

16-bit samples and Adam7 interlacing are planned work and currently return
explicit unsupported-feature errors.

## Quick start

```bash
moon check
moon test
moon run cmd/main
```

Expected demo output:

```text
MoonPNG decode demo
image: 1x1, format=RGBA8
pixel(0, 0): rgba(255, 0, 0, 255)
```

## Decode an image

```moonbit
match @moonpng.decode(png_bytes) {
  Ok(image) => {
    println("decoded: \{image.width}x\{image.height}")
    match image.pixel_at(0, 0) {
      Some(pixel) => println("red channel: \{pixel.red.to_uint()}")
      None => ()
    }
  }
  Err(error) => println(error.message())
}
```

`DecodedImage.pixels` stores four bytes per pixel in red, green, blue, alpha
order. Rows are contiguous from top to bottom.

## Inspect without decoding

Use `inspect` when only container metadata and chunk information are needed:

```moonbit
match @moonpng.inspect(png_bytes) {
  Ok(info) => println("PNG: \{info.width}x\{info.height}")
  Err(error) => println(error.message())
}
```

## Resource limits

The default decoder uses conservative bounds suitable for ordinary images.
Applications can choose tighter limits for untrusted uploads:

```moonbit
let limits : @moonpng.DecodeLimits = {
  max_chunk_size: 8 * 1024 * 1024,
  max_chunks: 1024,
  max_compressed_size: 16 * 1024 * 1024,
  max_inflated_size: 32 * 1024 * 1024,
  max_pixels: 8 * 1024 * 1024,
}
let result = @moonpng.decode_with_limits(png_bytes, limits)
```

The zlib layer is also reusable on its own through `inflate_zlib` and
`inflate_zlib_with_limit`.

## Architecture

The decode pipeline has five bounded stages:

1. inspect and validate the PNG container;
2. validate palette and transparency metadata;
3. concatenate consecutive IDAT payloads;
4. inflate the zlib stream and verify Adler-32;
5. reverse row filters, unpack samples, and convert them to RGBA8.

See [DESIGN.md](DESIGN.md) for the invariants and module boundaries.

## Roadmap

1. Decode 16-bit samples with documented RGBA8 downsampling.
2. Add Adam7 interlace reconstruction.
3. Add deterministic PNG encoding and streaming interfaces.
4. Add a browser demo, conformance fixtures, fuzzing, and benchmarks.

## Project status

This repository is being developed for the 2026 MoonBit open-source ecosystem
competition. The implementation is original MoonBit code based on public PNG,
zlib, and DEFLATE specifications. See [SOURCES.md](SOURCES.md) for provenance
notes.

## License

Apache-2.0.
