# Sources and provenance

MoonPNG is an original MoonBit implementation. No source code has been copied
or translated from an existing PNG library.

The format behavior is based on these public specifications:

- W3C, *Portable Network Graphics (PNG) Specification (Third Edition)*:
  <https://www.w3.org/TR/png-3/>
- ISO/IEC 15948:2004, *Portable Network Graphics (PNG): Functional
  specification*.

The CRC-32 implementation follows the polynomial and initialization/finalization
rules described by the PNG specification. The test vector `123456789 ->
CBF43926` is a standard CRC-32 check value. The structural PNG test fixture is
authored in this repository from its constituent chunk bytes; it contains no
third-party artwork or redistributed image.

Future dependencies, conformance suites, corpora, generated files, or borrowed
test fixtures must be added here with their source URL, version, license, and
scope of use before they enter the repository.
