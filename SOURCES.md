# Sources and licenses

| Material | Source | License and use |
| --- | --- | --- |
| LZMA/LZMA2 decoder and Delta filter dependency | [aurora0x27/lzma-mbt](https://github.com/aurora0x27/lzma-mbt), Mooncakes 0.1.0 | Apache-2.0; `lzma`, `lzma2` and `filters` public APIs, not vendored |
| Host I/O and asynchronous execution | [moonbitlang/async](https://github.com/moonbitlang/async), 0.22.5 | Apache-2.0; CLI/example/checks only |
| Standard library | [moonbitlang/core](https://github.com/moonbitlang/core) | Apache-2.0; toolchain dependency |
| 7z format and SDK description | [7z format](https://www.7-zip.org/7z.html), [LZMA SDK](https://www.7-zip.org/sdk.html) | SDK is Public Domain; format reference, no SDK code copied |
| Container parsing reference | [bodgit/sevenzip](https://github.com/bodgit/sevenzip/tree/bc7ebbd2043c386e3bab1bd04a64a62062890fc4), especially `types.go` | BSD-3-Clause; consulted for format structure and cross-checking. License retained in `licenses/sevenzip-BSD-3-Clause.txt` |
| Corpus source files | [lzma-mbt at e50568f7d8358045c39092210d140f6a5eec6971](https://github.com/aurora0x27/lzma-mbt/tree/e50568f7d8358045c39092210d140f6a5eec6971) | Apache-2.0; exact README.md, LICENSE, moon.mod under `corpus/source/lzma-mbt/` |
| Corpus packer | [7zr.exe](https://www.7-zip.org/a/7zr.exe), identifying itself as 26.04 (2026-10-05) | Public Domain reduced SDK executable; used to produce fixtures, not redistributed |
| Folder binding and coder output layout | [official 7zFormat.txt](https://github.com/ip7z/7zip/blob/main/DOC/7zFormat.txt) | Format reference consulted for the bounded linear pipeline reader; no source code copied |

The corpus's empty file, Unicode directory, manifest and project tests were
written for this repository. No external test cases or archive binaries were
copied. The complete 7-Zip application has additional license conditions and
must not be confused with the SDK's Public Domain terms. No py7zr code is used.

The two PCM WAV originals in `corpus/audio/` and their generator are
project-authored Apache-2.0 interoperability data. Their Delta-filtered archives
were generated with the same Public Domain 7zr, not copied from another project.
The filter algorithm is reused from `lzma-mbt`; this project implements the 7z
binding, size validation and member workflow integration.

Development was checked with official stable `moon 0.1.20261021` and
`moonc v0.10.17+093cb8f9c` (2026-10-21). Compiler executables were checked against
the official stable SHA-256 manifest. No performance or full 7-Zip compatibility
claim is made.
