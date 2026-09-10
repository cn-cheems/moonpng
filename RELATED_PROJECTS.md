# Related projects and scope

MoonPNG is an independent MoonBit implementation based on the PNG, zlib, and
DEFLATE specifications. It does not depend on or reuse source code from
`gmlewis/image/png`.

The existing [`gmlewis/image/png`](https://github.com/gmlewis/moonbit-image/tree/master/png)
package is a general-purpose PNG reader and writer based on Go's `image/png`
implementation. It exposes `decode`, `decode_config`, and `encode` around the
`gmlewis/image` image model and is licensed under Apache-2.0.

The projects necessarily overlap in basic PNG decoding and encoding. MoonPNG's
primary contribution is the defensive processing and diagnostics layer around
that format work:

| Area | `gmlewis/image/png` | MoonPNG |
| --- | --- | --- |
| Main purpose | General image loading and saving | Validation, diagnostics, bounded processing, and controlled rewriting |
| Container report | No public per-chunk inventory | Offsets, lengths, flags, and computed/read CRC values |
| Resource policy | No public per-call limits in the PNG API | Independent chunk, compressed, inflated, pixel, and text limits |
| Failure detail | General I/O and format errors | Typed failures for container, DEFLATE, palette, filtering, and limits |
| Text metadata | No public editing API | Bounded `tEXt`, `zTXt`, and `iTXt` reading and lossless rewriting |
| Incremental output | Writer-oriented codec API | Row callback and bounded IDAT fragments without retaining the full image |
| End-user tooling | Library package | Browser workbench and JSON-lines guard command |

Applications may use `moonpng-guard` to reject malformed or over-budget input
before passing accepted files to `gmlewis/image/png` when its broader image
model is desired. MoonPNG does not claim the shared baseline codec features as
an extension of that project's code.
