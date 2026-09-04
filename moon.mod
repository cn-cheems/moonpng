// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "cn-cheems/moonpng"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/cn-cheems/moonpng"

license = "Apache-2.0"

keywords = [ "png", "image", "codec", "crc32", "wasm" ]

preferred_target = "wasm-gc"

description = "A pure MoonBit PNG parser, validator, and codec toolkit."
