# Complete LZMA1 property reading

The 7z LZMA1 method (`03 01 01`) supports all 225 legal property combinations:
`lc=0..8`, `lp=0..4`, `pb=0..4`. LZMA1 permits `lc + lp > 4`; LZMA2 has its own
format-required `lc + lp <= 4` restriction, which remains enforced. This closes
the previous LZMA1 high-level decoder limitation without broadening LZMA2.

## A complete package workflow

```console
moon run app -- test --json corpus/lzma1/lc8-lp4-pb4.7z
moon run app -- extract --contents-only corpus/lzma1/lc3-lp2-pb2.7z . imported-lzma1
moon run app -- diff --json corpus/lzma1/lc8-lp4-pb4.7z corpus/lzma1/end-marker.7z
moon run checks/lzma1.mbtx -- wasm
moon run checks/lzma1.mbtx -- native
```

Each package contains the attributed Apache-2.0 README, license and Unicode-named
JSON manifest: three real files totaling 14,229 bytes. The comparison is identical
despite different property/termination/header encodings. The check exports those
original bytes and a separate 131,075-byte binary with repeated 64 KiB history.
It corrupts another archive and confirms nonzero status, empty stdout and no
published/staging directory. Native mode actually executes the native CLI.

`Archive::open`, reader/range, verify/audit, comparison and host export APIs are
unchanged. `Limits.lzma_probability_bytes` is a new optional resource setting,
defaulting to 16 MiB. The UInt32 table contains
`1846 + (768 << (lc + lp))` probabilities; all combinations fit the default.
The largest table needs 12,590,296 bytes. Its quota is independent of dictionary
and final-output quotas, and is checked during opening before table allocation.
Tests check the exact quota and one byte less, plus negative settings.

The decoder uses the bounded folder output as history and refuses distances
beyond either produced bytes or the declared dictionary (with the usual 4 KiB
minimum). It checks output before writing literals and overlapping matches.
The range coder must finish with code zero and consume the complete packed
input. If an end marker is present, it must be decoded explicitly after the
declared payload. Truncation, malformed history and unused/trailing bytes return
typed diagnostics; no partial member is returned. Range termination alone does
not prove intended contents without an external output length and integrity
information. All existing available CRC checks still apply; missing CRCs are
explicit and CRC is not authenticity. Quotas are not peak-RSS guarantees.

## Reuse and scope

`archive/lzma.mbt` adapts the LZMA1 symbol/range algorithms from
[aurora0x27/lzma-mbt e50568f7d8358045c39092210d140f6a5eec6971](https://github.com/aurora0x27/lzma-mbt/tree/e50568f7d8358045c39092210d140f6a5eec6971),
under Apache-2.0. Original license and exact source paths are retained in
[SOURCES.md](../SOURCES.md). Internal dependency packages are inaccessible to
downstream modules and are not imported. The adaptation adds a private flat
model, complete properties, probability budgets, checked output-backed history
and packed/end-marker validation. It replaces the previous `decode_alone` call;
LZMA2 and other reused filters continue through their existing dependency APIs.
No upstream test suite was copied, and no original-algorithm claim is made.

## Independent evidence and reproduction

Official 7-Zip Extra 26.05 generated every `lc/lp/pb` combination with:

```console
7za a CASE.7z README.md LICENSE 清单.json -t7z -m0=LZMA:lc=LC:lp=LP:pb=PB:d=64k -ms=on -mhc=off -mtm=off -mtc=off -mta=off
```

All 225 cases passed independent `7za t`, independent `7za x`, and exact original
byte comparison. The encoder reduces a requested dictionary for this small input;
the checked headers declare 16 KiB. Requested dictionary size is not confused
with the stored value. A separate `history.7z` uses a full 64 KiB dictionary and
project-authored deterministic binary data. `end-marker.7z` adds `eos=on` and
encoded headers; it too passes independent extraction and byte comparison.

`manifest.json` records parameter tags, sizes and SHA-256 for every matrix
archive. The archives are packed into `matrix.base64` solely as a portable test
transport: decoded bytes start with `M7L1`, version byte 1, UInt32-LE count 225,
then ordered records of three parameter bytes, UInt32-LE archive length and
complete archive bytes. Base64 lines are 256 ASCII characters. This avoids large
byte-array ASTs in the tested Windows compiler and is not a new public format.
The test checks all framing/tag counts, exact final consumption and every member
byte. The matrix has its own test package and runs on all four targets.

Additional tests cover malformed property sizes/values, zero output, literal
context extremes, the last allowed dictionary distance, unavailable history,
truncation, unused tails, optional end markers, budget limits, 256 deterministic
malformed byte families, failed-read recovery and preserved older archive behavior.
Required matrix cases are not skipped on `Unsupported`.

| Material | SHA-256 |
| --- | --- |
| `lc0-lp0-pb0.7z` | `633cf6b8a80e82ab50ece6705bbf5ed3a76d9e18cd3cbac2ee5c1c839b12e73c` |
| `lc3-lp2-pb2.7z` | `e0e78fbd73bd347a73f77ddb2620d42afc35e1b16d2c831ceacc2dd416182765` |
| `lc8-lp4-pb4.7z` | `6e6bfba7ede17f19212a13b1c26fe751ad0b2a5754eade9b836bde82d8b26a00` |
| `end-marker.7z` | `9330bad553c7cd0931a8bc005403577ce6cea810c47b75592dea0f31560522bd` |
| `history.7z` | `d96f4e3730a15e987d066dd15d083d37a5c1ba41552814e1ca683c2528296394` |
| `matrix.base64` | `53d59d3929b35bc1493a24157e25ae23563326a690f08709f21bbf72d420af58` |
| `manifest.json` | `3c491824e143cb25ff4555e97791e9721af93db7792eda5dc51b243295719b97` |

Regenerate to a **new** directory from the module root:

```console
moon run corpus/lzma1/generate.mbtx -- PATH_TO_7ZA26 NEW_DIRECTORY
```

The builder checks the producer banner, packing, testing, extraction and original
bytes; packer binaries are not redistributed or needed to run checked-in tests.
Compatibility completion still requires the remaining [input and publication
work](compatibility.md).
