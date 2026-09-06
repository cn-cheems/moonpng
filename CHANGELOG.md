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
- Added a decoded-pixel CLI demo and decoder design documentation.
