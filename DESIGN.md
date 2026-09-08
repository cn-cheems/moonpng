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
For Adam7 images, each pass is sized, unfiltered, and converted independently
before its pixels are scattered into the final row-major image. Filter history
therefore resets at every pass boundary as required by PNG.

`convert_to_rgba` is the only stage that depends on PNG color type. Packed
samples are read most-significant-bit first within each byte, with row padding
discarded before the next row. Grayscale samples are scaled across the full
8-bit range; indexed samples are checked before their palette entry is read.
For 16-bit channels, the most significant byte is retained while transparency
comparisons still use the complete 16-bit sample.

## Public data model

- `PngInfo` and `ChunkInfo` describe a validated container.
- `DecodedImage` owns row-major RGBA8 bytes.
- `Rgba8` is returned by the bounds-checked `pixel_at` helper.
- `DecodeLimits` makes memory and expansion policies explicit.
- `PngError` covers container failures; `DecodeError` covers both container and
  pixel-data failures.

## Encode pipeline

`encode` validates dimensions and the exact pixel buffer length for grayscale,
grayscale-alpha, RGB, or RGBA input before allocation. It writes the matching
PNG color type without adding unused channels. For each row, the default
strategy tries all five PNG filters and
selects the lowest sum of absolute signed-byte magnitudes, breaking ties by
filter number. The encoder then splits the filtered bytes into legal
65,535-byte stored DEFLATE blocks, adds the zlib Adler-32 checksum, and writes
IHDR, IDAT, and IEND chunks with CRC-32 values. Callers may bound IDAT payloads;
the zlib stream is split at byte boundaries and the chunks remain consecutive.
The same input and options always produce the same PNG bytes.

`encode_rows_with_options` is the bounded counterpart for generated or large
images. It pulls one exact-length row at a time, retains only that row and its
predecessor for filtering, and writes stored DEFLATE blocks directly into a
caller-sized IDAT payload buffer. Adler-32 is updated as filtered bytes pass
through, so neither the full pixel input, filtered image, nor zlib stream is
materialized. The output callback receives the PNG signature and complete PNG
chunks in order. If a later row has the wrong length, the function returns an
error but does not retract fragments already delivered to the callback.

## Text metadata

Text extraction starts with strict container inspection, then parses `tEXt`,
`zTXt`, and `iTXt` chunks in file order. Keywords, Latin-1 text, UTF-8 fields,
compression flags, methods, and language tags are validated before an entry is
returned. Compressed text uses the same zlib decoder as image data, with
independent limits for entry count, encoded bytes, and decoded bytes.

The metadata writer validates every field before producing output. Addition and
replacement insert complete text chunks before the first IDAT chunk, preserving
all unrelated chunks and image data byte-for-byte. Compressed entries use the
deterministic stored-DEFLATE encoder, so identical input produces identical PNG
bytes.

## Security invariants

- No chunk payload is read before its declared range and CRC are validated.
- Dimension multiplication is checked before allocation.
- Compressed and decompressed sizes have independent limits.
- A DEFLATE distance cannot refer before the beginning of output.
- A DEFLATE match cannot grow output beyond its configured limit.
- The inflated byte count must exactly match the expected scanline layout.
- Every Adam7 pass is bounded before slicing or allocating its scanlines.
- Palette indices are checked before color or alpha entries are accessed.
- Text chunk count, encoded text, and decoded text have independent limits.
- Text fields are validated before writers allocate the output PNG.
- Row-oriented encoding retains memory proportional to row width and the
  configured IDAT payload limit, independent of image height.
- Unsupported formats fail explicitly rather than producing approximate pixels.

## Portability

The library uses MoonBit bytes, arrays, integers, and result types only. It does
not call a native compression library and has no target-specific implementation
branch. CI exercises native, JavaScript, Wasm, and Wasm GC builds on Windows,
macOS, and Linux.

## Browser workbench

The browser entry point is a thin MoonBit controller compiled with the
JavaScript backend. Browser bindings are limited to file selection, canvas
painting, table updates, and download creation; parsing, checksums, decoding,
encoding, and pixel comparison all call the same `cn-cheems/moonpng` package as
the command-line example and tests. Uploaded bytes do not leave the page. The
demo applies tighter decode and text limits than the library defaults to keep
the page responsive on ordinary devices. It also displays validated text
entries and exposes add, edit, format-conversion, and removal controls. Each
change is converted into `TextEntry` values and validated by the MoonBit
metadata writer before a new download is exposed. Invalid edits leave the last
verified download unchanged. The metadata-only download is produced directly
from the current validated PNG, so IDAT and every non-text chunk remain
byte-for-byte identical. A separate pixel re-encoding remains available to
demonstrate the complete codec pipeline without conflating the two operations.
