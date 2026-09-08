# MoonPNG

MoonPNG is a pure MoonBit PNG codec toolkit. It validates the PNG
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
- decodes color types 0, 2, 3, 4, and 6;
- reconstructs all seven Adam7 passes for interlaced images;
- expands 1-, 2-, and 4-bit packed grayscale and indexed-color samples;
- downsamples 16-bit channels to RGBA8 using the most significant byte;
- validates and expands `PLTE` palettes;
- supports `tRNS` transparency for grayscale, truecolor, and indexed images;
- reads, validates, adds, and replaces `tEXt`, `zTXt`, and `iTXt` metadata,
  including bounded zlib decompression and UTF-8 validation;
- converts decoded output to row-major RGBA8;
- deterministically encodes 8-bit grayscale, grayscale-alpha, RGB, and RGBA
  pixels using their native PNG color types;
- offers fixed and adaptive selection across all five PNG row filters;
- splits zlib output across caller-sized consecutive IDAT chunks;
- encodes row-provided images into bounded output fragments without retaining
  the complete source image or compressed stream;
- includes a local browser workbench for upload, inspection, decoded preview,
  interactive text metadata editing, deterministic re-encoding, and
  pixel-level round-trip verification;
- runs on MoonBit's native, JavaScript, Wasm, and Wasm GC targets.

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

## Browser workbench

Build the MoonBit JavaScript target and serve the repository root:

```bash
moon build cmd/web --target js --release
python3 -m http.server 8000
```

Open <http://localhost:8000/web/>. On Windows, `py -3 -m http.server 8000`
can be used for the second command. The workbench starts with a generated
sample and accepts local PNG files by picker or drag and drop. Uploaded files
stay in the browser. Validated text metadata is displayed alongside the chunk
table. Entries can be added, edited, converted between compressed and
uncompressed formats, or removed before downloading the re-encoded image.
Invalid keywords, encodings, language tags, and size-limit violations are
reported without replacing the current download.

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

## Read and write text metadata

```moonbit
let entries = [
  @moonpng.latin1_text("Author", "cn-cheems"),
  @moonpng.international_text(
    "Title",
    "MoonPNG 示例",
    language_tag="zh-Hans",
    translated_keyword="标题",
  ),
]
match @moonpng.add_text_entries(png_bytes, entries) {
  Ok(updated) => println("updated PNG: \{updated.length()} bytes")
  Err(error) => println(error.message())
}
```

`read_text_entries` returns every textual chunk in file order.
`replace_text_entries` removes existing textual chunks and inserts the supplied
entries before image data while preserving unrelated chunks byte-for-byte. Set
`compressed=true` on either entry constructor for `zTXt` or compressed `iTXt`.
`read_text_entries_with_limits` lets applications bound entry count and both
encoded and decoded text sizes independently.

## Encode an image

```moonbit
let pixels = b"\xff\x00\x00\xff"
match @moonpng.encode_rgba8(1U, 1U, pixels) {
  Ok(png_bytes) => println("encoded \{png_bytes.length()} bytes")
  Err(error) => println(error.message())
}
```

The default encoder selects the lowest-cost filter for each row and uses stored
DEFLATE blocks. Its output is deterministic and does not require a platform
compression library. `encode_rgba8_with_options` can force None, Sub, Up,
Average, or Paeth filtering when reproducible filter control is needed.

Use `encode` with `PixelGray8`, `PixelGrayAlpha8`, `PixelRgb8`, or `PixelRgba8`
to avoid storing channels that an image does not need.

`encode_with_idat_chunk_size` bounds each IDAT payload while retaining one
continuous zlib stream. This is useful when a writer or transport prefers
smaller independently checksummed PNG chunks.

For images that should not be held in one pixel buffer, `encode_rows` requests
one row at a time and passes the PNG signature and each complete chunk to an
output callback:

```moonbit
let rows = [b"\xff\x00\x00", b"\x00\x00\xff"]
let fragments : Array[Bytes] = []
let result = @moonpng.encode_rows(
  1U,
  2U,
  @moonpng.PixelRgb8,
  row => rows[row],
  fragment => fragments.push(fragment),
)
```

`encode_rows_with_options` also accepts a filter strategy and maximum IDAT
payload size. Its working memory is bounded by the row width and IDAT limit,
not image height. Because output is progressive, a bad row can be reported
after the signature or earlier chunks have already reached the callback.

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

1. Add broader conformance fixtures and property-based malformed-input tests.
2. Add fuzzing, benchmarks, and an optimized DEFLATE encoder.

## Project status

This repository is being developed for the 2026 MoonBit open-source ecosystem
competition. The implementation is original MoonBit code based on public PNG,
zlib, and DEFLATE specifications. See [SOURCES.md](SOURCES.md) for provenance
notes.

## License

Apache-2.0.
