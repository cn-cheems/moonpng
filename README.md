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
- compresses standalone zlib streams with cost-aware bounded LZ77 matching,
  one-step lazy matching, and fixed Huffman codes;
- selects stored, fixed-Huffman, or shortest-output automatic compression for
  buffered PNG encoding;
- splits zlib output across caller-sized consecutive IDAT chunks;
- streams stored, fixed-Huffman, or per-scanline automatic compression into
  bounded output fragments without retaining the complete source image or
  compressed stream;
- includes a local browser workbench for upload, inspection, decoded preview,
  lossless text metadata editing, deterministic pixel re-encoding, and
  pixel-level round-trip verification;
- runs on MoonBit's native, JavaScript, Wasm, and Wasm GC targets.

## Quick start

```bash
moon check
moon test
moon run cmd/main
moon run cmd/bench --target native --release
```

Expected demo output:

```text
MoonPNG decode demo
image: 1x1, format=RGBA8
pixel(0, 0): rgba(255, 0, 0, 255)
```

`cmd/bench` compares stored, fixed-Huffman, and automatic compression on four
deterministic RGBA8 workloads: a solid image, a gradient, repeated tiles, and
high-entropy noise. Every encoded PNG is decoded and checked byte-for-byte
before its size is reported, so the command serves as both a reproducible size
benchmark and an end-to-end codec smoke test.

| Sample | Raw RGBA8 | Stored PNG | Fixed PNG | Auto PNG | Auto / raw | Selected |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Solid | 65,536 | 65,737 | 695 | 695 | 1.1% | Fixed |
| Gradient | 65,536 | 65,737 | 632 | 632 | 1.0% | Fixed |
| Tiles | 65,536 | 65,737 | 738 | 738 | 1.1% | Fixed |
| Noise | 65,536 | 65,737 | 68,584 | 65,737 | 100.3% | Stored |

Sizes are deterministic bytes produced by the current encoder. The noise case
also demonstrates why automatic selection retains stored blocks when fixed
Huffman coding would increase the output size.

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
uncompressed formats, or removed before downloading the result.
Invalid keywords, encodings, language tags, and size-limit violations are
reported without replacing the current download. The workbench offers two
outputs: a metadata-only result that preserves IDAT and every non-text chunk
byte-for-byte, and a separately re-encoded result that demonstrates the codec's
pixel round trip.

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
Average, or Paeth filtering when reproducible filter control is needed. The
same options select stored blocks, fixed-Huffman compression, or automatic
comparison of both outputs:

```moonbit
let options : @moonpng.EncodeOptions = {
  filter_strategy: @moonpng.FilterAdaptive,
  compression_strategy: @moonpng.CompressionAuto,
}
let result = @moonpng.encode_rgba8_with_options(1U, 1U, pixels, options)
```

`CompressionAuto` chooses the shorter complete zlib stream and uses stored
blocks when lengths tie. This makes the result deterministic while avoiding
fixed-Huffman expansion on literal-heavy data.

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

`encode_rows_with_options` also accepts filter and compression strategies plus
a maximum IDAT payload size. Its working memory is bounded by the row width and
IDAT limit, not image height. Because output is progressive, a bad row can be
reported after the signature or earlier chunks have already reached the
callback. Fixed mode emits one DEFLATE block per filtered scanline and resets
its matcher after each row, keeping memory independent of image height.
`CompressionAuto` encodes a row-local Fixed candidate, compares its exact bit
length with a Stored candidate, and commits the shorter block. It prefers
Stored on a tie and may mix both block types in one zlib stream.

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
`inflate_zlib_with_limit`. `compress_zlib_stored` and `compress_zlib_fixed`
provide explicit deterministic compression paths, while `compress_zlib`
accepts the same Stored, Fixed, or Auto strategy used by the PNG encoder:

```moonbit
let compressed = @moonpng.compress_zlib(
  b"repeated repeated repeated",
  @moonpng.CompressionAuto,
)
match @moonpng.inflate_zlib(compressed) {
  Ok(original) => println("restored \{original.length()} bytes")
  Err(error) => println(error.message())
}
```

The compressor searches a 32 KiB history window through bounded hash chains,
emits matches from 3 through 258 bytes, and writes one fixed-Huffman DEFLATE
block. A candidate is emitted only when its length and distance codes cost
fewer bits than the equivalent literals. The encoder also looks one byte ahead
and defers a match when the next position produces a larger saving. Buffered
PNG encoding uses the same implementation for `CompressionFixed` and
`CompressionAuto`. Row-oriented Fixed encoding reuses the matcher separately
for each scanline and writes consecutive blocks through the same bit stream.
Row-oriented Auto performs the same comparison per scanline so candidate memory
is released before the next row. Text metadata compression continues to use
stored blocks.

## Architecture

The decode pipeline has five bounded stages:

1. inspect and validate the PNG container;
2. validate palette and transparency metadata;
3. concatenate consecutive IDAT payloads;
4. inflate the zlib stream and verify Adler-32;
5. reverse row filters, unpack samples, and convert them to RGBA8.

See [DESIGN.md](DESIGN.md) for the invariants and module boundaries.

## Roadmap

1. Extend deterministic mutation coverage with randomized malformed-input tests.
2. Tune match-search limits against a documented, redistributable image corpus.
3. Add fuzzing and dynamic-Huffman encoding.

## Project status

This repository is being developed for the 2026 MoonBit open-source ecosystem
competition. The implementation is original MoonBit code based on public PNG,
zlib, and DEFLATE specifications. See [SOURCES.md](SOURCES.md) for provenance
notes.

## License

Apache-2.0.
