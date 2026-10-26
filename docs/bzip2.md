# BZip2 member reading and expansion limits

The 7z BZip2 method (`04 02 02`, no properties) works through the existing
archive/reader/verifier/auditor/export interfaces. No executable is called by
the decoder. Container, physical-input, folder and member CRC policies remain
the same; BZip2 also verifies every internal block CRC and combined stream CRC.

```console
moon run app -- test corpus/bzip2/v2605-solid.7z
moon run app -- extract --contents-only corpus/bzip2/v2605-solid.7z out audio-bzip2
moon run checks/bzip2.mbtx -- wasm
moon run checks/bzip2.mbtx -- native
```

Create `out` first and use a new destination. The check compares audio/JSON bytes
against the attributed originals and verifies two additional generated binary
files. The native checker executes the native CLI. Checked-in data needs no
private infrastructure or external decompressor during normal tests.

The decoder accepts level digits 1–9, canonical Huffman trees up to 20 bits,
MTF/run coding, multiple BWT blocks, legacy randomized blocks and complete
concatenated BZip2 streams. Trailing bytes must form another valid stream;
arbitrary suffixes are refused. Format padding inside the final byte is ignored.
The bit reader, selector/tree bounds, original pointer, transformed block size
and final output length are checked. No partial output escapes after an error.

`dictionary_bytes` limits each compressed header's `level * 100000` block size
before building inverse-transform data. `working_bytes` bounds declared coder
outputs; `output_bytes` bounds final folder output. **A 100 KB transformed block
can expand far beyond 100 KB after RLE.** The decoder checks each emitted byte
and repeated run against the declared output, rather than allocating a guessed
RLE buffer. Limits describe controlled data, not peak RSS. The complete node
output is retained; this is not a public streaming codec API.

## Independent fixtures and provenance

Official 7-Zip Extra 19.00/26.05 packed, tested and extracted the five `.7z`
cases. The ordinary cases contain the two Apache-2.0 PCM files and JSON manifest
(32,908 bytes). Their auto-selected Delta filter also exercises graph composition.
Solid mode uses two folders; separate mode uses three. `runs.bin` is 1,100,000
ASCII `a` bytes; `blocks.bin` has 210,123 deterministic bytes
`(i * 73 + i / 257) & 255`. Its 100 KB BZip2 setting produces three codec blocks
inside one 7z folder, checked separately by the tests.

| Fixture | SHA-256 |
| --- | --- |
| v1900-solid.7z | `d34b42180cc022bb378a3bc799af062efa2aa2147d8b5aecf2b07be9adc3bb8c` |
| v2605-solid.7z | `d34b42180cc022bb378a3bc799af062efa2aa2147d8b5aecf2b07be9adc3bb8c` |
| v2605-separate.7z | `dab0f4680aaca68f410c21019290f3a9408b76490581f26672838a3106418e56` |
| v2605-runs.7z | `aa7d88f178b7f4c82554fbddb733168fa11613e025be53268ee844d8d4411085` |
| v2605-blocks.7z | `11e4b6ee68be70d4cf09566782084560cace8f658520ea22ac15915c6f8db8b0` |
| runs.bz2 | `9147a8604648ae4beb9642e6db456f3aab746428197b4d74ed4b581de06c925a` |
| blocks.bz2 | `36432e57c78147253c9b30982564f4960fa206351587df2957006255f8acfdca` |
| randomized.bz2 | `1a6d0ea566d77157ca00f600c0b6d22e27e41a8a170f4b702b49dff643e919fa` |

The raw `.bz2` files test private codec invariants, not a new public `.bz2`
container API. The legacy fixture starts with project-authored 1,536-byte data
`i % 251`. Its generator applies the published randomization schedule, compresses
that data, sets the randomized flag and repairs block/stream CRCs to describe
the original bytes. Neither input has RLE1 runs. Independent 7-Zip test/extraction
then verifies the result; this is not solely a decoder/inverse round trip.

```console
moon run corpus/bzip2/generate.mbtx -- PATH_TO_7ZA19 PATH_TO_7ZA26 NEW_DIRECTORY
```

The implementation partially adapts the Go BSD-3-Clause reader and retains
the bzip2 1.0.8 randomization table under its original license. Source notices,
licenses and reuse boundaries are in [SOURCES.md](../SOURCES.md). No external
test cases were copied. Broader [reading compatibility](compatibility.md),
including PPMd and encryption, is still being implemented.
