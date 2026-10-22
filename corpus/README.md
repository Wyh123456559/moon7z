# Interoperability corpus

`source/` contains real Apache-2.0 package metadata/documentation, a JSON import
manifest, an empty file and a Unicode empty directory. Source provenance and
licenses are in `../SOURCES.md`. All four archives contain the same five files
(14,550 bytes) and two directories. The packer is 7zr 26.04, run from `source/`:

Git does not retain empty directories. Before regenerating, create `source/空目录`
if it is absent; its directory entry is already present in the archive fixtures.

```console
7zr a ../copy-plain.7z ./* -t7z -m0=Copy -ms=off -mhc=off -mtm=off -mtc=off -mta=off
7zr a ../lzma-solid.7z ./* -t7z -m0=LZMA -ms=on -mhc=on -md=64k -mtm=off -mtc=off -mta=off
7zr a ../lzma2-solid.7z ./* -t7z -m0=LZMA2 -ms=on -mhc=on -md=64k -mtm=off -mtc=off -mta=off
7zr a ../lzma2-separate.7z ./* -t7z -m0=LZMA2 -ms=off -mhc=off -md=64k -mtm=off -mtc=off -mta=off
```

Regenerate to **new** filenames; 7-Zip's add command updates an existing archive.
Attributes may differ across hosts, so regenerated archive bytes need not match.
The invariant is equality of paths, kinds, empty members and every file byte.
Portable unit tests embed the checked-in binaries and originals with Moon's
built-in resource tool; users need no 7-Zip installation to run those tests.

For an independent manual check, run `7zr t ARCHIVE` and `7zr x ARCHIVE -oNEW_DIR`,
then compare that directory with `source/`. All archives were tested with 7zr;
Moon7z tests compare each extracted member directly with the originals.

`binary.7z` is a separate boundary fixture containing `binary/payload.bin`
(archived as `payload.bin`), with bytes 0 through 255. It is project-authored
test data under Apache-2.0, packed by the same 7zr version using Copy, no solid
block, plain header and all three timestamp options off. It verifies binary
member extraction and CLI stdout without decoding bytes as text.
