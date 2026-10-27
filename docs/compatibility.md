# Reading compatibility: current evidence and completion target

This is an implementation contract, not a claim that version 0.1.0 is complete.
Normative references: official
[7zFormat.txt](https://github.com/ip7z/7zip/blob/main/DOC/7zFormat.txt) and
[Methods.txt](https://github.com/ip7z/7zip/blob/main/DOC/Methods.txt).
Freeze the reference revisions when preparing a release report.

## The endpoint

The proposed **1.0 common-reader profile** covers the 7z 0.3/0.4 container
structures and the finite methods listed below, including encrypted headers/data,
multi-pack-stream graphs and split input. It is a target requiring all rows to
pass before claiming completion. Resource policy may refuse an oversized input;
an unimplemented format feature must never be relabeled a resource-policy limit.

The profile does not mean every future third-party codec or every file supported
by the 7-Zip application. RAR/ZIP/XZ are separate containers. Archive writing is
outside this reader project. Unknown methods remain a typed unsupported result;
unknown metadata must be preserved with semantics clearly stated, or refused.

Archive reading must retain links, anti-items and metadata as data. Disk export
is a separate policy: it may refuse dangerous entries rather than create links,
delete files or silently omit metadata. Contents-only export must stay explicit.

| Area | Current 0.1.x evidence | Required for the 1.0 profile |
| --- | --- | --- |
| File versions | Header major 0 / minor 0–4 accepted; independently generated 0.3/0.4 archives from five official versions and libarchive, [21 required cases](producers.md) | Maintain a complete per-feature matrix; acceptance of a version byte alone is insufficient |
| Headers | Plain/encoded headers, additional streams, external names/times/attributes/folder definitions, ordered opaque archive properties; [placement and framing evidence](external.md) | Preserve mappings/integrity across remaining file-property/input paths; unsupported structures stay explicit |
| Inventory | Files/directories, original UTF-16 names/IDs, FILETIMEs/attributes, UInt64 start positions, anti-items, links/special entries and ordered opaque file properties; [read/export evidence](semantics.md) | Preserve these semantics across remaining codecs and input paths; no destructive restoration |
| Coder graph | Bounded acyclic graphs, independently mapped packed inputs, four-input BCJ2, arbitrary stored coder order; [five real cases](bcj2.md) | Preserve this mapping/integrity behavior for every remaining codec and header structure |
| Compression | Copy, LZMA1, LZMA2, PPMd7, raw DEFLATE and BZip2; [LZMA1](lzma1.md), [PPMd7](ppmd.md), [DEFLATE](deflate.md) and [BZip2](bzip2.md) include independent producer/boundary evidence | Preserve method/property compatibility across remaining input work; each format's limits remain explicit |
| LZMA properties | LZMA1 all 225 legal property combinations independently encoded/extracted; probability-table budget, exact consumption and optional end markers. LZMA2 retains its format's lc+lp≤4 rule | Retain this behavior across remaining source/volume/header paths |
| Filters | Delta, classic x86 BCJ, ARM64, RISC-V, ARM, ARM-Thumb, PowerPC, IA64, SPARC, Swap2/Swap4; [classic evidence](filters.md), [RISC-V evidence](riscv.md) | Preserve valid method/property behavior across remaining input/header paths; classic methods use empty properties, unlike ARM64/RISC-V |
| Encryption | Password API, AES-256-CBC/SHA-256 derivation with cumulative work limits, encrypted headers/data and [four real cases](encrypted.md), missing/wrong password recovery | Preserve these contracts across remaining input/header paths; CRC is not authenticated encryption |
| SFX/embedded input | In-memory and [seekable UInt64 discovery/explicit offsets](source-sfx.md), exact prefix/payload/suffix views, split SFX and actual 4 GiB+ reading/verification; no executable is run | Maintain corpus, boundary, error and envelope-preservation evidence across supported targets |
| Split input | Ordered numeric sets with variable sizes, count/total budgets and missing/reordered diagnostics; bounded import, [seekable composition](seekable.md) and [split SFX](source-sfx.md) | Preserve tested behavior across source adapters; alphabetic split names remain outside the current input APIs |
| Input scale | Existing bounded memory API plus async UInt64 files/volumes/SFX and actual 4 GiB+ verification | Maintain cross-platform evidence and explicit per-folder/source/total policies |
| Integrity | All available pack/folder/member CRCs in verified scope; missing member CRCs explicit | Same behavior for all new graph/method/volume paths; CRC is not authenticity |
| Publishing | No-replace staging, exact selected IDs, metadata returned rather than applied | Preserve these contracts while expanding readable inputs; unsafe export must fail clearly |

Every pending row is a real gap. In particular, remaining
publication and independent installation must not be relabeled complete merely
because additional codecs now pass. A larger test count cannot substitute for
these rows.

## Producer and feature matrix

The release matrix must identify **producer software version separately from
container version**. The baseline producer set has now been run: official
7-Zip 19.00, 23.01, 24.09, 25.01 and 26.05, plus libarchive/bsdtar 3.8.9.
The 21 baseline cases and their SHA-256 evidence are in
[producer matrix](producers.md). They exercise Copy/LZMA/LZMA2 and the declared
header/layout modes; pending codecs, encryption and other structures remain
pending even though their producer version appears in this baseline.
Current corpus and commands are in [corpus/README.md](../corpus/README.md).

For each supported method/structure, record producer/version, arguments, original
input provenance/license, header/solid mode, declared feature, expected inventory,
content digest, successful independent extraction and Moon7z result. Required
fixtures cannot be counted as passed or silently skipped on `Unsupported`.
Negative fixtures have a separately recorded expected typed failure.

Input dimensions include empty files/directories, Unicode, duplicate names,
different member ordering, solid boundaries, multiple folders, missing/present
CRCs, timestamps/attributes, malformed properties, truncation, output budgets,
password failure and recovery. For byte conversion, compare against independent
packing/extraction rather than only encode/decode functions from one dependency.
Deterministic JSON must round-trip without loss of UInt64 values.

## Coherent implementation sequence

1. **Coverage foundation:** publish the reuse/API comparison and this matrix;
   run real producer interoperability with no skips for required features.
2. **Unary filter completeness:** validate 7z method IDs, properties, whole-solid
   history and independent output for the additional branch/swap filters.
3. **Container completeness:** retain archive/file properties and additional
   streams; generalize graph and pack-stream mapping, then implement BCJ2.
4. **Codec and encrypted reading:** add the missing compression methods and
   bounded password/AES handling, including encoded headers.
5. **Input and release completeness:** volume/SFX/seekable input, independently
   installed consumer, published module and a release matrix whose required
   rows all pass on the supported target/OS set.

Each step includes implementation, boundary/regression tests, executable workflow,
attribution and generated interfaces where needed. Later steps may expose
additional work; this sequence does not promise completion by a contest deadline.

## Evidence required before the completion claim

- All target rows implemented; each required producer/feature case has a passing
  result, not an unsupported skip.
- Fresh-clone format/interface checks, strict compilation and tests on Wasm,
  Wasm-GC, JavaScript and native; host workflows actually run on native Linux,
  macOS and Windows, as well as Wasm.
- An independent downstream project installs the published module and imports a
  real archive through the documented public API.
- Complete license/source notes, visible limitations and unchanged refusal of
  malformed input; no silent data removal in conversions.

The currently passing CI only certifies the implemented subset. This target is
not an organizer-approved definition of completeness; any different required
codec/version scope must be reconciled before a completion claim.
