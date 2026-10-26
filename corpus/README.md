# Interoperability corpus

The [producer matrix](../docs/producers.md) adds 21 required archives generated
with official 7-Zip 19.00/23.01/24.09/25.01/26.05 and libarchive 3.8.9, recording
both producer and container versions plus SHA-256 values. Unlike the original
four archives below, those new official cases retain all three timestamps.
Source files are shared; actual archived metadata may differ by producer/host.

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

## Delta-filtered audio and byte data

The additional `branches/` corpus covers ARM, ARM-Thumb, PowerPC, IA64, SPARC,
Swap2 and Swap4 with 12 independently packed archives, two solid members and an
odd 65,539-byte original. Its standalone generator performs 7zr pack/test/extract
and compares the extracted originals. See [filter evidence and regeneration](../docs/filters.md).

`audio/left.wav` and `audio/right.wav` are valid RIFF PCM files: stereo signed
16-bit samples at 16 kHz, 4,096 frames each. They contain deterministic sawtooth
signals with different phases; they are interoperability data, not recorded
user audio. Regenerate the originals from the module root with:

```console
moon run corpus/audio/generate.mbtx
```

`delta-solid.7z` contains both WAV files in one solid folder, with a distance-4
Delta filter and LZMA2. `delta256-copy.7z` contains the existing all-byte-values
payload with a distance-256 Delta filter and Copy. Both have plain headers and
no timestamps. Generate to new archive paths with 7zr 26.04:

```console
# From corpus/audio/
7zr a ../delta-solid.7z left.wav right.wav -t7z -m0=Delta:4 -m1=LZMA2:d=64k -ms=on -mhc=off -mtm=off -mtc=off -mta=off
# From corpus/binary/
7zr a ../delta256-copy.7z payload.bin -t7z -m0=Delta:256 -m1=Copy -mhc=off -mtm=off -mtc=off -mta=off
```

Both archives passed `7zr t`. Unit tests compare original bytes, exercise solid
history across the member boundary, CRCs, resource limits and truncated input.
`moon run checks/filters.mbtx -- wasm` verifies the CLI's test, binary stdout
and disk export against every original. Replace `wasm` with `native` to execute
the native application. CI runs both workflows without needing 7-Zip installed.

## x86 BCJ program and instruction boundaries

`x86/program.elf` is a real, freestanding Linux x86-64 executable built from
`x86/program.S`. It writes `moon7z x86 fixture` and a newline, then exits. No
runtime is linked. On Linux x86-64, from the module root:

```console
cc -nostdlib -no-pie -Wl,--build-id=none -o corpus/x86/program.elf corpus/x86/program.S
./corpus/x86/program.elf
moon run corpus/x86/generate.mbtx
```

The checked-in ELF was built with GCC 10.5.0 on Ubuntu. Recompiling with another
linker can change ELF bytes; repack the archive into a new path if regenerating.
The raw members exercise forward/backward jumps, overlapping opcodes, bit-24
sign extension, noncanonical immediates and incomplete tails. A five-byte CALL
is split across `part-a.bin` / `part-b.bin`; resetting BCJ per member is wrong.
All fixtures are project-authored Apache-2.0 data, with provenance in SOURCES.md.

From `corpus/x86/`, using the same 7zr 26.04:

```console
7zr a ../bcj-lzma2.7z program.elf -t7z -m0=BCJ -m1=LZMA2:d=64k -mhc=on -mtm=off -mtc=off -mta=off
7zr a ../bcj-lzma.7z program.elf -t7z -m0=BCJ -m1=LZMA:d=64k -mhc=off -mtm=off -mtc=off -mta=off
7zr a ../bcj-solid.7z part-a.bin part-b.bin -t7z -m0=BCJ -m1=Copy -ms=on -mhc=off -mtm=off -mtc=off -mta=off
```

All three passed `7zr t`. Portable tests and `checks/filters.mbtx` compare every
extracted byte with the originals. The ELF is not executed during extraction or
CI; its one-time native fixture run is separate from Moon7z's native tests.

## ARM64 program and filter offset boundaries

`arm64/generate.mbtx` constructs project-authored Apache-2.0 originals. The
144-byte `program.elf` has one read/execute load segment, ELF64/AArch64 machine
type, entry `0x400078`, and six instruction words: BL to a helper, MOV X0/0,
MOV X8/93, SVC 0, ADRP X1/current-page and RET. Its header/load segment were
inspected with `readelf -h -l`; it was **not executed on an ARM64 CPU**.
The generator writes the explicit ELF fields and instructions; no runtime or
third-party executable code is linked.

`a-head.bin` / `b-tail.bin` split a 4,403-byte instruction sequence after three
bytes, so a BL instruction crosses members. The sequence crosses a 4 KiB page,
contains positive/negative BL, ADRP immediate range boundaries, unconverted B
and NOP instructions, and three trailing bytes. Regenerate from the module root:

```console
moon run corpus/arm64/generate.mbtx
```

Generate archives to new paths from `corpus/arm64/`, using 7zr 26.04:

```console
7zr a ../arm64-lzma2.7z program.elf -t7z -m0=ARM64 -m1=LZMA2:d=64k -mhc=on -mtm=off -mtc=off -mta=off
7zr a ../arm64-offset.7z a-head.bin b-tail.bin -t7z -m0=ARM64:4096 -m1=Copy -ms=on -mhc=off -mtm=off -mtc=off -mta=off
7zr a ../arm64-wrap.7z a-head.bin b-tail.bin -t7z -m0=ARM64:4294967292 -m1=LZMA:d=64k -ms=on -mhc=off -mtm=off -mtc=off -mta=off
```

All three passed `7zr t`. The offset fixtures contain four property bytes;
the final offset wraps during decoding of the first two instructions. The
portable tests compare every original byte and reject malformed/alignment
properties, truncation, corruption and resource excess. `checks/filters.mbtx`
also tests verification, selective binary stdout and contents-only export for
every archive on Wasm and native. These runs execute Moon7z, not the AArch64
program fixture.
