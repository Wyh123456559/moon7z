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
| File versions | Header major 0 / minor 0–4 accepted; current fixtures are mainly 7zr 26.04, 0.4 | Independently generated 0.3 and 0.4 archives; acceptance of a version byte alone is insufficient |
| Headers | Plain and single-stream compressed headers, start/next/header CRC checks, ordered opaque archive properties | Additional/external metadata streams, all declared header placements and encoded-header mappings |
| Inventory | Files, directories, zero-length files, solid and separate folders, original UTF-16 names/IDs, three FILETIMEs and attributes | Anti-items, links/special-file metadata and extension properties retained without destructive export |
| Coder graph | At most eight unary coders in one linear decode path, one pack stream per folder | General bounded graph validation, multiple packed inputs, BCJ2 and every mapped output/substream |
| Compression | Copy, LZMA1 and LZMA2 | Also PPMd7, BZip2 and DEFLATE; method/property compatibility tested against independent encoders |
| LZMA properties | Codec-backed supported lc/lp range; exact decoded size and dictionary policy enforced | All property combinations emitted by the declared producer matrix, or a documented remaining blocker |
| Filters | Delta, classic x86 BCJ, ARM64, ARM, ARM-Thumb, PowerPC, IA64, SPARC, Swap2/Swap4; see [evidence](filters.md) | Also RISC-V and all valid properties; classic methods use empty properties, unlike ARM64/RISC-V |
| Encryption | Explicitly unsupported | Password API, AES-256/SHA-256 7z derivation with work limits, encrypted headers and data, missing/wrong-password cases |
| Split/SFX input | Explicitly unsupported; signature must be at byte zero | Ordered volume source, missing/reordered volume diagnostics and bounded signature discovery for SFX; no executable is run |
| Input scale | In-memory bytes, controlled sizes at most 0x3fffffff | Seekable bounded input with UInt64 offsets; retain a deliberate in-memory convenience API |
| Integrity | All available pack/folder/member CRCs in verified scope; missing member CRCs explicit | Same behavior for all new graph/method/volume paths; CRC is not authenticity |
| Publishing | No-replace staging, exact selected IDs, metadata returned rather than applied | Preserve these contracts while expanding readable inputs; unsafe export must fail clearly |

Every pending row is a real gap. In particular, AES, BCJ2, PPMd and BZip2 must
not remain excluded while the project is described as having completed this
profile. A small demo or a larger test count cannot substitute for these rows.

## Producer and feature matrix

The release matrix must identify **producer software version separately from
container version**. Planned reproducible producer set: official 7-Zip 19.00,
23.01, 24.09, 25.01 and 26.05, plus libarchive/bsdtar with its exact observed
version. These version strings are targets, not a claim they were all run.
Current checked-in corpus and commands are in [corpus/README.md](../corpus/README.md).

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
