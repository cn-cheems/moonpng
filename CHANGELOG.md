# Changelog

## 0.1.0 - Unreleased

- Added the initial strict PNG container inspector.
- Added PNG CRC-32, chunk bounds and naming validation.
- Added IHDR metadata and structural validation.
- Added configurable resource limits, tests, and an embedded CLI demo.
- Added a pure MoonBit zlib/DEFLATE inflater supporting stored, fixed-Huffman,
  and dynamic-Huffman blocks.
- Added Adler-32 validation, bounded back-references, and trailing-data checks.
- Added all five PNG scanline filters and RGBA8 pixel output.
- Added non-interlaced 8-bit grayscale, truecolor, grayscale-alpha, and RGBA
  decoding, including grayscale and truecolor `tRNS` transparency.
- Added indexed-color decoding with validated `PLTE` palettes and palette
  `tRNS` transparency.
- Added 1-, 2-, and 4-bit packed grayscale and indexed-color decoding, including
  row padding, byte-oriented filtering, and grayscale sample scaling.
- Added 16-bit decoding for grayscale, truecolor, grayscale-alpha, and RGBA,
  with full-sample transparency comparison and documented RGBA8 downsampling.
- Added Adam7 reconstruction for every supported color type and bit depth,
  including packed indexed samples and independent filtering per pass.
- Added deterministic RGBA8 encoding with stored DEFLATE blocks, PNG checksums,
  multi-block output, round-trip tests, and input validation.
- Added caller-selected None, Sub, Up, Average, and Paeth encoding filters plus
  a deterministic per-row adaptive strategy.
- Added compact 8-bit grayscale, grayscale-alpha, and RGB encoding alongside
  RGBA, with native PNG color types and round-trip coverage.
- Added configurable IDAT payload sizing with consecutive multi-chunk output,
  per-chunk CRC validation, and decoder round-trip coverage.
- Added row-oriented encoding with bounded IDAT fragments, incremental Adler-32,
  cross-block scanline handling, and explicit row-length validation.
- Added a MoonBit-driven browser workbench with local file loading, decoded
  canvas preview, chunk inspection, re-encoding, and pixel round-trip checks.
- Added bounded `tEXt`, `zTXt`, and `iTXt` extraction with Latin-1, UTF-8,
  language-tag, compression-method, and aggregate-size validation.
- Added deterministic text insertion and replacement plus browser metadata
  display and preservation during re-encoding.
- Added a decoded-pixel CLI demo and decoder design documentation.
