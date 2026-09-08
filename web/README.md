# MoonPNG browser workbench

The workbench is a static page driven by the MoonBit JavaScript target. It
loads PNG files locally, validates their structure and CRC values, decodes them
to RGBA8 for canvas display, re-encodes the pixels, and decodes the result again
to verify exact pixel equality. Validated `tEXt`, `zTXt`, and `iTXt` entries are
shown in a separate table and retained in the downloaded PNG.

From the repository root, build the browser entry point:

```bash
moon build cmd/web --target js --release
```

Serve the repository root so the page can load the generated bundle:

```bash
python3 -m http.server 8000
```

Then open <http://localhost:8000/web/>. Windows users can start the server with
`py -3 -m http.server 8000`. The generated JavaScript stays under the ignored
`_build` directory and is never treated as handwritten source.
