# MoonPNG

MoonPNG is a pure MoonBit PNG parser, validator, and codec toolkit in progress.
The first working milestone provides a strict, resource-bounded PNG container
inspector with no external runtime dependency.

Repository: <https://github.com/cn-cheems/moonpng>

## Working MVP

- validates the 8-byte PNG signature;
- parses PNG chunks with overflow and bounds checks;
- validates chunk names, the reserved bit, and CRC-32;
- validates IHDR dimensions, color/bit-depth combinations, compression, filter,
  and interlace methods;
- enforces IHDR/IDAT/IEND structural requirements;
- exposes chunk flags and image metadata through a reusable MoonBit API;
- offers configurable limits for chunk size and chunk count;
- runs on MoonBit's Wasm GC backend without FFI.

Pixel decompression and encoding are planned work. The current API deliberately
does not claim to decode IDAT image data.

## Quick start

```bash
moon check
moon test
moon run cmd/main
```

Expected demo output:

```text
MoonPNG structural inspection demo
image: 1x1, bit_depth=8, color_type=6
chunks: 3
- IHDR offset=8 length=13 crc=ok critical=true
- IDAT offset=33 length=0 crc=ok critical=true
- IEND offset=45 length=0 crc=ok critical=true
```

## Library usage

```moonbit
match @moonpng.inspect(png_bytes) {
  Ok(info) => println("PNG: \{info.width}x\{info.height}")
  Err(error) => println(error.message())
}
```

For untrusted input, tune the resource limits explicitly:

```moonbit
let result = @moonpng.inspect_with_limits(
  png_bytes,
  max_chunk_size=8 * 1024 * 1024,
  max_chunks=1024,
)
```

## Roadmap

1. Add real file input to `moonpng inspect` and more metadata chunks.
2. Implement zlib/deflate integration and scanline unfiltering.
3. Decode PNG color types 0/2/3/4/6 and `tRNS` transparency.
4. Add Adam7 interlace reconstruction.
5. Add deterministic encoding, a browser demo, conformance fixtures, fuzzing,
   and benchmarks.

## Project status

This repository is being developed for the 2026 MoonBit open-source ecosystem
competition. The implementation is original MoonBit code based on the public
PNG specification. See [SOURCES.md](SOURCES.md) for provenance notes.

## License

Apache-2.0.
