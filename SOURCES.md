# Sources and provenance

MoonPNG is an original MoonBit implementation. No source code has been copied
or translated from an existing PNG library.

The format behavior is based on these public specifications:

- W3C, *Portable Network Graphics (PNG) Specification (Third Edition)*:
  <https://www.w3.org/TR/png-3/>
- ISO/IEC 15948:2004, *Portable Network Graphics (PNG): Functional
  specification*.
- IETF RFC 1950, *ZLIB Compressed Data Format Specification version 3.3*:
  <https://www.rfc-editor.org/rfc/rfc1950>.
- IETF RFC 1951, *DEFLATE Compressed Data Format Specification version 1.3*:
  <https://www.rfc-editor.org/rfc/rfc1951>.

The CRC-32 implementation follows the polynomial and initialization/finalization
rules described by the PNG specification. The test vector `123456789 ->
CBF43926` is a standard CRC-32 check value. The Adler-32 implementation and
DEFLATE bitstream behavior follow RFC 1950 and RFC 1951. Small compressed test
vectors were produced with Python's standard `zlib` module from byte sequences
authored for this repository. PNG fixtures are assembled in tests from their
constituent chunk bytes and contain no third-party artwork or redistributed
images.

Future dependencies, conformance suites, corpora, generated files, or borrowed
test fixtures must be added here with their source URL, version, license, and
scope of use before they enter the repository.
