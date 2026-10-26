# DEFLATE resource imports

Applications can import PCM audio and structured metadata packed with the 7z
DEFLATE method through the same `Archive::open`, reader, verifier, auditor and
exporter APIs. The library does not run an external codec. ZIP, gzip and zlib
containers are outside this method; it consumes raw DEFLATE within 7z.

```console
moon run app -- test corpus/deflate/v2605-solid.7z
moon run app -- extract --contents-only corpus/deflate/v2605-solid.7z out audio-import
moon run checks/deflate.mbtx -- wasm
moon run checks/deflate.mbtx -- native
```

Create the parent `out` first and use a new destination name. The checker
compares every exported byte with `corpus/audio/{left,right}.wav` and
`corpus/source/清单.json`. The two WAV originals and JSON are attributed in
[SOURCES.md](../SOURCES.md); all are Apache-2.0 corpus data. No private services
or 7-Zip installation are needed to run the checked-in corpus.

The decoder follows [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951).
It supports stored blocks, fixed/dynamic canonical Huffman trees, cross-block
32 KiB history and overlapping copies. Trees, repeat counts, end markers,
stored-length complements, reserved symbols and distances are validated.
Each literal or match is checked against its declared coder output before
appending, and the final decoded length must agree exactly. Full trailing bytes
are refused; unused bits within the final byte are format padding. No source
bytes are silently discarded.

The format's 32,768-byte dictionary requirement is checked against
`dictionary_bytes` before decoding. `working_bytes` and `output_bytes` retain
their graph/final-output meanings. The decoder currently keeps the bounded
complete node output, rather than exposing a streaming codec API. There is no
performance claim. No public API change is needed for this additional 7z method.

## Independent evidence

Official 7-Zip Extra 19.00 and 26.05 packed, tested and independently unpacked
all cases. Each has three files totaling 32,908 bytes; auto-selected Delta
preprocessing of PCM audio exercises filter composition. Solid mode groups the
two audio files and leaves the JSON in a second folder; separate mode has three
folders. Level zero is an encoder option, not a claim that its emitted blocks
are stored blocks. Stored/fixed/dynamic formats are separately covered by
project-authored bit-level tests, including all literal bytes, distance 32,768,
repeat overlap, malformed trees, truncation, trailing data and error recovery.

| Case | Producer / options | Archive SHA-256 |
| --- | --- | --- |
| v1900-solid | 19.00, Deflate:x=9, solid, header compression enabled | `a363a85ff78a7a62072cc5a917b29574f08093061597ae94372df129d5852d70` |
| v2605-solid | 26.05, same settings; identical archive bytes are expected here | `a363a85ff78a7a62072cc5a917b29574f08093061597ae94372df129d5852d70` |
| v2605-separate | 26.05, Deflate:x=1, separate, header compression enabled | `60e9e8d21b8383e013a7d64752a0f27bebce1dd5fed06b2e377c5d9ffbe48578` |
| v2605-level0 | 26.05, Deflate:x=0, solid, plain header | `34a154969e06ad7082ddc30a16b7d3077393357d10de9555ff148ea18cf67f27` |

```console
moon run corpus/deflate/generate.mbtx -- PATH_TO_7ZA19 PATH_TO_7ZA26 NEW_DIRECTORY
```

The generator validates version banners and extracted originals. Producer
executables are testing tools, not distributed or linked dependencies.
The broader [compatibility target](compatibility.md) remains incomplete.
