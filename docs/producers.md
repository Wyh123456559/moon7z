# Actual producer compatibility evidence

Evidence generated on 2026-10-26. Producer software version and 7z container
version are separate fields; a compatible version byte alone is not a pass.

| Actual producer | Container | Required checked cases |
| --- | --- | --- |
| Official 7-Zip Extra 19.00 (x64) | 0.4 | Copy/plain/separate; LZMA/compressed/solid; LZMA2/compressed/solid; LZMA2/plain/separate |
| Official 7-Zip Extra 23.01 (x64) | 0.4 | Same four modes |
| Official 7-Zip Extra 24.09 (x64) | 0.4 | Same four modes |
| Official 7-Zip Extra 25.01 (x64) | 0.4 | Same four modes |
| Official 7-Zip Extra 26.05 (x64) | 0.4 | Same four modes |
| Windows bsdtar/libarchive 3.8.9, liblzma 5.8.3 | 0.3 | Default LZMA, compressed header and solid folder |

There are **21 required cases**. Each contains the same five files and two
directories as `corpus/source/`, including a real upstream license/README/module
file, an import manifest, an empty file and a Unicode empty directory. Official
producer cases retain creation/access/modification times. The fixture manifest
records each archive's SHA-256, original file digests and exact producer version.
These files are newly packed test data; none was copied from a peer project's
test suite.

The generator checks actual executable banners, packs every mode into a new
directory, has bsdtar list every archive, and has official 7-Zip 26.05 test and
extract all cases. Every extracted file is compared byte-for-byte with its
original, and directory presence is checked. The independent extraction report
does not itself claim Moon7z passed: portable tests and the separate workflow
perform that check using the checked-in files.

## Repeat the Moon7z verification

No external packer is needed for these commands:

```console
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon run checks/producers.mbtx -- wasm
moon run checks/producers.mbtx -- native
```

All 21 archives are embedded in portable tests, which compare original member
bytes, stable names/kinds, declared output size, selective reads, JSON round
trips, truncation, limits, corrupt Copy payloads and recovery. The CLI workflow
checks the complete required-ID set and each archive's recorded SHA-256 and
container version, exports every case through the real CLI, and compares every
file and the Unicode empty directory. An unsupported result is a failure,
not a skipped compatibility case. CI invokes this workflow for Wasm and native.

## Regenerate the independent evidence

Get the standalone console executables from the official
[7-Zip downloads](https://www.7-zip.org/download.html) / linked release assets,
and install bsdtar/libarchive with 7zip writing enabled. From the module root,
pass the five packer paths in version order, bsdtar and a **new** output directory:

```console
moon run corpus/producers/generate.mbtx -- /tools/19.00/7za /tools/23.01/7za /tools/24.09/7za /tools/25.01/7za /tools/26.05/7za /tools/bsdtar /tmp/new-producer-corpus
moon run checks/producers.mbtx -- wasm /tmp/new-producer-corpus
```

For the exact checked manifest, use the recorded versions on Windows. On another
host, verify its producer/version fields and resulting metadata; the generator
records the actual bsdtar banner. It expects those precise software versions and
container versions and refuses an existing output directory. New timestamps or
filesystem attributes can change archive SHA-256 values; equality of new archive
bytes to the checked-in bytes is not the cross-producer invariant. The invariant
is correct inventory and every original file byte, with retained metadata.

## What this does not certify

This baseline covers the listed codec/header/layout combinations for those
producers. It does not cover their entire feature set, all platforms on which
they run, AES, BCJ2, PPMd, BZip2, additional streams, split volumes or large
seekable inputs. BCJ2 has [separate five-case evidence](bcj2.md); the other gaps remain explicit rows in the
[1.0 completion target](compatibility.md). Passing these 21 cases is not a
claim that the complete reader target or contest acceptance is achieved.
