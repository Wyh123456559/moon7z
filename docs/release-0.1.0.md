# Moon7z 0.1.0 release evidence

Published module: [`Wyh123456559/moon7z@0.1.0`](https://mooncakes.io/docs/Wyh123456559/moon7z/).
The registry reports publication at **2026-10-31 02:45:36 UTC**. Publication
used the authenticated `Wyh123456559` Mooncakes account and returned `200 OK`.

Release source: [`e732bf31c49456756ce50a8f6356fc2fd62506a2`](https://github.com/Wyh123456559/moon7z/commit/e732bf31c49456756ce50a8f6356fc2fd62506a2).
Its [six-job verification workflow](https://github.com/Wyh123456559/moon7z/actions/runs/41161347237)
passed: portable Wasm/Wasm-GC/JavaScript and native Linux/macOS/Windows.
Later documentation commits do not replace the immutable registry artifact.

The uploaded archive and the ZIP independently downloaded by the package manager
have the same SHA-256:

```text
28ed5e3225c9f30403acc48bfe39902ca2bd67b704464c5b279b5d4b01dceaf2
```

The archive is 5,374,049 bytes. It includes licenses, attributed corpus inputs
and 138 generated test-resource declarations. These declarations must be
distributed because dependencies do not execute `dev_build` rules. The
`checks/package.mbtx` regression check extracts a fresh package, checks every
declared resource, excludes caches and passes strict Wasm checking plus all
197 tests. The publishing command independently checked the extracted archive.

## Independent installed consumer

The consumer lived outside the repository, declared only registry dependencies
and had no workspace membership or local source override. `moon add` downloaded
version 0.1.0, and `moon tree` resolved:

```text
local/moon7z-consumer@0.1.0
  Wyh123456559/moon7z@0.1.0
    aurora0x27/lzma-mbt@0.1.0
    moonbitlang/async@0.22.5
    moonbitlang/x@0.5.5
```

The three-file program in [the installation guide](install.md) was compiled and
executed against the installed library. Inputs were unchanged copies of
`corpus/lzma2-solid.7z` and `corpus/copy-plain.7z`; their existing source/license
notes apply. Validation used `moon 0.1.20261023`, `moonc v0.10.17+d971670cd`.
Older toolchains were not validated by this release check.

| Installed-library workflow | Actual executions |
| --- | --- |
| Synchronous verification, duplicate-ID batch reads and byte/metadata comparison | Wasm, Wasm-GC, JavaScript, Linux native |
| Positioned file verification, batch read and selected no-replace export | Wasm, Linux native |
| Positioned audit, grouped ranges and comparison across Copy/LZMA2 repacking | Wasm, Linux native |

The input contained five files totaling 14,550 bytes. The exported 52-byte JSON
manifest matched the original bytes on both host targets. Linux native ran in
Ubuntu 22.04 under WSL and exported into a Linux `/tmp` filesystem. WSL's
Windows-mounted filesystem rejected the no-replace directory rename with an
I/O error; the validation did not count that refused export as success. The
existing no-overwrite and trusted-parent contracts remain unchanged.

## Reproduce

Follow [install.md](install.md) in a new directory, then use the public fixture
from the release revision:

```console
moon add Wyh123456559/moon7z@0.1.0
moon tree
moon run --target wasm . -- /path/to/lzma2-solid.7z 6 /existing/parent imported
moon run --target native . -- /path/to/lzma2-solid.7z 6 /existing/parent imported-native
```

Use a new destination each time. The fixture is available in the
[release corpus](https://github.com/Wyh123456559/moon7z/blob/e732bf31c49456756ce50a8f6356fc2fd62506a2/corpus/lzma2-solid.7z).
The independent consumer did not re-run the complete producer/codec matrix or
large-file corpus; those have separate repository CI and provenance records.
This initial public release does not certify every 7-Zip feature or complete
the entire [1.0 common-reader profile](compatibility.md).
