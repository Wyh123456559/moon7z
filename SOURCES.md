# Sources and licenses

The API-level reuse boundary and current ecosystem comparison are documented in
[docs/ecosystem.md](docs/ecosystem.md). The project does not claim that the LZMA,
LZMA2 or adapted BCJ algorithms are original. `Sxy11112/moon7z` is an independently
reviewed direct peer, not a dependency or a source of code/fixtures here.

| Material | Source | License and use |
| --- | --- | --- |
| LZMA/LZMA2 decoder and Delta/branch filter dependency | [aurora0x27/lzma-mbt](https://github.com/aurora0x27/lzma-mbt), Mooncakes 0.1.0 | Apache-2.0; `lzma`, `lzma2` and `filters` public APIs, not vendored; exact calls are in docs/ecosystem.md |
| Host I/O and asynchronous execution | [moonbitlang/async](https://github.com/moonbitlang/async), 0.22.5 | Apache-2.0; CLI/example/checks only |
| Standard library | [moonbitlang/core](https://github.com/moonbitlang/core) | Apache-2.0; toolchain dependency |
| 7z format and SDK description | [7z format](https://www.7-zip.org/7z.html), [LZMA SDK](https://www.7-zip.org/sdk.html) | SDK is Public Domain; format reference; the BCJ adaptation is recorded separately below |
| Container parsing reference | [bodgit/sevenzip](https://github.com/bodgit/sevenzip/tree/bc7ebbd2043c386e3bab1bd04a64a62062890fc4), especially `types.go` | BSD-3-Clause; consulted for format structure and cross-checking. License retained in `licenses/sevenzip-BSD-3-Clause.txt` |
| Corpus source files | [lzma-mbt at e50568f7d8358045c39092210d140f6a5eec6971](https://github.com/aurora0x27/lzma-mbt/tree/e50568f7d8358045c39092210d140f6a5eec6971) | Apache-2.0; exact README.md, LICENSE, moon.mod under `corpus/source/lzma-mbt/` |
| Corpus packer | [7zr.exe](https://www.7-zip.org/a/7zr.exe), identifying itself as 26.04 (2026-10-05) | Public Domain reduced SDK executable; used to produce fixtures, not redistributed |
| Folder binding and coder output layout | [official 7zFormat.txt](https://github.com/ip7z/7zip/blob/main/DOC/7zFormat.txt) | Format reference consulted for bounded graph validation and stream mapping; no source code copied |
| x86 BCJ decoder | [Igor Pavlov, Bra86.c, 7-Zip 21.07](https://github.com/ip7z/7zip/blob/21.07/C/Bra86.c), file dated 2021-02-09 | Public Domain; decoder translated into `archive/bcj.mbt`, with whole-folder state and explicit UInt32 arithmetic. Original notice retained in source and `licenses/7zip-BCJ-Public-Domain.txt` |
| BCJ2 decoder | [Bcj2.c](https://github.com/ip7z/7zip/blob/26.05/C/Bcj2.c) and [Bcj2.h](https://github.com/ip7z/7zip/blob/26.05/C/Bcj2.h), Igor Pavlov, 7-Zip 26.05 | Public Domain; bounded whole-folder MoonBit adaptation in `archive/bcj2.mbt`; original notices in `licenses/7zip-BCJ2-Public-Domain.txt`. The BSD-3-Clause sevenzip BCJ2 reader was also consulted; its retained license applies to that reference |
| BCJ method/properties reference | [BcjRegister.cpp](https://github.com/ip7z/7zip/blob/main/CPP/7zip/Compress/BcjRegister.cpp), [BcjCoder.h](https://github.com/ip7z/7zip/blob/main/CPP/7zip/Compress/BcjCoder.h) | Consulted to establish the classic 7z method ID, zero initial pointer and absence of property support; no C++ source copied |
| ARM64 method, properties and alignment | [BranchRegister.cpp](https://github.com/ip7z/7zip/blob/main/CPP/7zip/Compress/BranchRegister.cpp), [BranchMisc.cpp](https://github.com/ip7z/7zip/blob/main/CPP/7zip/Compress/BranchMisc.cpp), [Bra.c](https://github.com/ip7z/7zip/blob/main/C/Bra.c) | Format/algorithm cross-check only; no ARM64 SDK source copied. The decoder is the Apache-2.0 dependency's public `bcj_arm64` API |

The corpus's empty file, Unicode directory, manifest and project tests were
written for this repository. No external test cases or archive binaries were
copied. The complete 7-Zip application has additional license conditions and
must not be confused with the SDK's Public Domain terms. No py7zr code is used.

The two PCM WAV originals in `corpus/audio/` and their generator are
project-authored Apache-2.0 interoperability data. Their Delta-filtered archives
were generated with the same Public Domain 7zr, not copied from another project.
The Delta filter algorithm is reused from `lzma-mbt`; this project implements the 7z
binding, size validation and member workflow integration.

`corpus/x86/program.S` is project-authored Apache-2.0 source. Its freestanding
ELF executable was built by GCC 10.5.0 / GNU binutils on Linux x86-64 with
`-nostdlib -no-pie -Wl,--build-id=none`; no C runtime or third-party program code
was linked. The two raw instruction members and their generator are also
project-authored. Three BCJ archives were packed and tested with 7zr 26.04.
The dependency's x86 filter is not used: its output differs on the sign-extension
vector `E8 00 00 00 FF`; the local decoder is checked against the independent
7-Zip packer and has a regression test for this case. This is not a claim about
all upstream filter behavior.

`corpus/arm64/` contains project-authored Apache-2.0 test data and a deterministic
MoonBit generator. It constructs a minimal ELF64/AArch64 binary with six explicit
instruction words and a separate BL/ADRP boundary sequence. No compiler runtime,
third-party program binary or external test suite is included. `readelf` checked
its ELF header and load segment; the AArch64 program was not executed. Three
ARM64 archives were independently packed and tested by 7zr 26.04, including
nonzero and wrapping initial offsets. See `corpus/README.md` for commands and
the distinction between program fixture bytes and native Moon7z execution.

`corpus/branches/` contains project-authored Apache-2.0 deterministic instruction
and byte data. Twelve archives were generated, tested and independently unpacked
with 7zr 26.04; no peer fixtures or external test vectors were copied. ARM,
ARM-Thumb, PowerPC, IA64 and SPARC transforms are dependency calls, not new
algorithms. Swap2/Swap4 group reversal is project code. Official
[BranchRegister.cpp](https://github.com/ip7z/7zip/blob/main/CPP/7zip/Compress/BranchRegister.cpp),
[BranchMisc.h](https://github.com/ip7z/7zip/blob/main/CPP/7zip/Compress/BranchMisc.h)
and [Methods.txt](https://github.com/ip7z/7zip/blob/main/DOC/Methods.txt) were
consulted for method IDs and the difference between classic empty properties
and ARM64/RISC-V offset properties; no additional C/C++ code was copied.

`corpus/properties/properties.7z` is a project-authored transformation of the
existing Copy corpus with three opaque archive-level metadata records. Its
generator repairs framing CRCs and checks independent 7zr test/extraction against
the originals. The official reader's
[7zIn.cpp](https://github.com/ip7z/7zip/blob/main/CPP/7zip/Archive/7z/7zIn.cpp)
was consulted to confirm variable UInt64 property IDs (`ReadID`) and bounded
value skipping; no C++ code was copied. Metadata is retained here rather than
skipped. JSON Base64 coding uses `moonbitlang/core/encoding/base64` (Apache-2.0).

`corpus/producers/` contains 21 newly generated archives of the same attributed
source tree: official 7-Zip Extra 19.00, 23.01, 24.09, 25.01 and 26.05, plus
Windows bsdtar/libarchive 3.8.9. Actual producer banners were checked during
generation. Binaries came from the official [download page](https://www.7-zip.org/download.html)
and linked ip7z/7zip release assets, and are not redistributed. Unlike 7zr,
7za Extra has LGPL and BSD components; no code was copied from these binaries
or linked into Moon7z. bsdtar/libarchive (BSD-2-Clause) is a test oracle only.
Input SHA-256 and archive SHA-256 values are recorded in `manifest.json`;
hashing in standalone development/check scripts uses
`moonbitlang/x@0.5.5/crypto` (Apache-2.0), not a runtime library dependency.

Development was rechecked on 2026-10-26 with official stable
`moon 0.1.20261023` and `moonc v0.10.17+d971670cd` (2026-10-23).
Windows compiler/runtime/formatter/interface executables were checked against
the current official stable SHA-256 manifest. No performance or full 7-Zip
compatibility claim is made.
