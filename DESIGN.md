# MoonPNG design

MoonPNG separates container validation from pixel decoding so callers can
inspect metadata without allocating buffers proportional to image dimensions.

## Decode pipeline

`inspect_with_limits` validates the signature and every chunk before image data
is used. Length arithmetic is checked before offsets are advanced. CRC-32 is
verified over the chunk type and payload, and IDAT chunks must be consecutive.

`collect_idat` copies validated IDAT payloads into one bounded zlib stream. An
unknown critical chunk stops decoding because silently ignoring it could change
the meaning of the image.

`parse_color_data` validates `PLTE` and `tRNS` placement and size before pixel
allocation. Indexed-color images require a palette, palette size is bounded by
both the PNG limit and bit depth, and transparent palette entries may not
outnumber palette entries.

`inflate_zlib_with_limit` validates the RFC 1950 header, rejects preset
dictionaries, and decodes all three RFC 1951 block kinds. Canonical Huffman
codes are reversed for DEFLATE's least-significant-bit-first representation.
Every output append and back-reference is checked against the output limit.
The final Adler-32 value is compared before inflated bytes are returned.

`unfilter_scanlines` reconstructs rows into a separate buffer. Left, above, and
upper-left values always come from bytes that have already been reconstructed.
Byte conversion provides the modulo-256 arithmetic required by PNG filters.

`convert_to_rgba` is the only stage that depends on PNG color type. Packed
samples are read most-significant-bit first within each byte, with row padding
discarded before the next row. Grayscale samples are scaled across the full
8-bit range; indexed samples are checked before their palette entry is read.
Keeping this step separate leaves 16-bit downsampling as a contained future
addition.

## Public data model

- `PngInfo` and `ChunkInfo` describe a validated container.
- `DecodedImage` owns row-major RGBA8 bytes.
- `Rgba8` is returned by the bounds-checked `pixel_at` helper.
- `DecodeLimits` makes memory and expansion policies explicit.
- `PngError` covers container failures; `DecodeError` covers both container and
  pixel-data failures.

## Security invariants

- No chunk payload is read before its declared range and CRC are validated.
- Dimension multiplication is checked before allocation.
- Compressed and decompressed sizes have independent limits.
- A DEFLATE distance cannot refer before the beginning of output.
- A DEFLATE match cannot grow output beyond its configured limit.
- The inflated byte count must exactly match the expected scanline layout.
- Palette indices are checked before color or alpha entries are accessed.
- Unsupported formats fail explicitly rather than producing approximate pixels.

## Portability

The library uses MoonBit bytes, arrays, integers, and result types only. It does
not call a native compression library and has no target-specific implementation
branch. CI exercises native, JavaScript, Wasm, and Wasm GC builds on Windows,
macOS, and Linux.
