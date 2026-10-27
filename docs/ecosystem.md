# Ecosystem comparison and implementation provenance

Review date: 2026-10-26. Module names, not short repository names, identify
projects. `Wyh123456559/moon7z` and `Sxy11112/moon7z` are different modules.

## Direct and adjacent projects

| Project and checked version | Public boundary | Relationship to this project |
| --- | --- | --- |
| [Sxy11112/moon7z](https://github.com/Sxy11112/moon7z/tree/6804168772a3419436f6512b1c8f260c037c4ca9), registry 0.1.0 | `SevenZ::open`, `entries`, `streams`, `extract_all`, `extract(name)`; own Copy/LZMA1/LZMA2 decoding; plain/compressed headers and solid members | **Direct overlap in basic container reading and extraction.** Its checked README explicitly excludes filters, AES, volumes, BCJ2 and PPMd/BZip2/Deflate. Those statements describe that revision, not all future versions. |
| [aurora0x27/lzma-mbt](https://github.com/aurora0x27/lzma-mbt), registry 0.1.0 | LZMA/LZMA2/XZ stream coding; `lzma.decode_alone`, `lzma2.decode_lzma2`, filter functions | Dependency, not a competing 7z member/container workflow. Moon7z does not implement or claim ownership of its range coder, dictionary engine or reused filters. |
| [lin2077-zeming/MoonXZ](https://github.com/lin2077-zeming/MoonXZ), registry 0.4.6 | `lib.compress`, `decompress`, `.lzma` helpers and XZ reader/writer APIs | Adjacent stream format. Its README snapshot still names 0.4.4; registry version and README claims must not be treated as identical. Not used as a dependency. |
| [bikallem/compress](https://github.com/bikallem/compress), registry 0.3.4 | Compression streams including DEFLATE and BZip2 | Adjacent codec APIs, not a 7z member workflow. Source was inspected for reuse; this published version's legacy `moon.mod.json` is rejected by the current stable toolchain. No code or tests copied into Moon7z; it is not a dependency. |
| [bodgit/sevenzip](https://github.com/bodgit/sevenzip/tree/bc7ebbd2043c386e3bab1bd04a64a62062890fc4) (Go) | General 7z reader using existing codecs and typed members | Container structure reference; not the implementation being wholly ported. BSD-3-Clause notice retained. |

All four checked MoonBit modules declare Apache-2.0 in the registry. The direct
peer's checked commit is dated 2026-10-24, and its registry release is dated
2026-10-24. MoonXZ's checked registry release is also dated 2026-10-24;
lzma-mbt 0.1.0 is dated 2026-09-29; compress 0.3.4 is dated 2026-03-25.
Dates are evidence of a release or checked commit, not a maintenance guarantee.

The direct peer was reviewed through its README and public declarations in
`signature.mbt`, `header.mbt` and `extract.mbt`. Its code, fixtures and scripts
are not incorporated into this repository. No claim is made that its tests fail
or that this project is faster or universally safer.

## What is independently implemented here

The independent value is a verified 7z import pipeline that can select, inspect,
compare, audit and publish members without discarding their original metadata,
with a versioned path toward complete reading of a declared common 7z profile.

Current additional public boundaries include:

- `Archive::verify` with optional per-file CRC coverage and explicit missing
  counts; folder-local auditing with machine-readable errors;
- ID-based reads and grouped byte-range requests, preserving duplicate original
  names and request order without using names as unique identifiers;
- resource limits before controlled allocation/decoding, complete member mapping
  and integrity checks for all siblings in selected solid folders;
- deterministic comparison by actual bytes and original metadata, with duplicate
  names refused as ambiguous;
- selected path planning and contents-only staged exports that refuse replacement
  and remove staged files after a late data failure;
- 7z coder bindings, filter property validation and whole-folder reconstruction
  beyond the direct peer's checked Copy/LZMA-only boundary.

These are concrete implementation differences, but do not erase the basic API
overlap. A contest that excludes all overlap even between independent readers
would need to judge this contribution explicitly; this document is not a claim
of ecosystem uniqueness or approval.

## Exact reused-code boundary

| Material | Use in Moon7z | Ownership / license |
| --- | --- | --- |
| `aurora0x27/lzma-mbt@0.1.0/lzma` | `decode_alone`: a temporary LZMA_Alone framing supplies 7z properties and the declared output size | Upstream Apache-2.0 decoder |
| `aurora0x27/lzma-mbt@0.1.0/lzma2` | `decode_lzma2`: raw LZMA2 data and dictionary size; Moon7z checks chunk/output budgets before the call | Upstream Apache-2.0 decoder |
| `aurora0x27/lzma-mbt@0.1.0/filters` | `delta_decode`, `bcj_arm64`, `bcj_arm`, `bcj_armthumb`, `bcj_powerpc`, `bcj_ia64`, `bcj_sparc`; independent 7-Zip cases exercise each used filter | Upstream Apache-2.0 algorithms |
| `archive/bcj.mbt` | Classic x86 BCJ decoding translated from Igor Pavlov's `Bra86.c` (7-Zip 21.07) | Public Domain adaptation, not an original algorithm |
| `archive/bcj2.mbt` | Four-input reconstruction adapted from 7-Zip 26.05 BCJ2 | Public Domain adaptation |
| `archive/riscv.mbt` | Scalar RISC-V JAL/AUIPC decoding and 7z offset integration | Public Domain 7-Zip 26.05 Bra.c adaptation |
| `archive/deflate.mbt` | Bounded whole-node raw DEFLATE decoding integrated with 7z graph/integrity policies | Project code from RFC 1951 format rules; the established algorithm is not claimed as novel |
| `archive/bzip2.mbt`, `bzip_random.mbt` | Bounded BZip2 reading, CRCs and legacy de-randomization | Partial Go BSD-3-Clause adaptation and bzip2-licensed table; exact provenance in SOURCES.md |
| `archive/ppmd.mbt`, `ppmd_memory.mbt`, `ppmd_model.mbt` | Checked offset-arena, PPMdH model/allocator and 7z range decoder | Public Domain 7-Zip 26.05 SDK adaptation; Igor Pavlov / Dmitry Shkarin notices retained |
| `moonbitlang/x@0.5.5/crypto` and `archive/crypto.mbt` | Existing AES/SHA primitives plus 7z password/property/work-budget integration | Upstream Apache-2.0 cryptography; project-authored bounded 7z integration, not a new cryptographic algorithm |
| `archive/binary.mbt`, `streams.mbt`, `files.mbt`, `open.mbt` | 7z framing, bounded fields, coder topology, inventory and decode integration | Project code; format references and consulted BSD reference recorded in SOURCES.md |
| `reader.mbt`, `ranges.mbt`, `paths.mbt`, `compare.mbt`, `audit.mbt`, `report.mbt`, `host/` | Public workflow logic and diagnostics | Project code, Apache-2.0 |

There is no runtime invocation of 7-Zip, libarchive, Python or the peer module.
Independent packers are development/test oracles only. The complete 7-Zip
application has mixed licensing; the SDK's Public Domain terms must not be
applied to the entire application. [SOURCES.md](../SOURCES.md) remains the
file-level source/fixture attribution record.

## Search evidence and uncertainty

Queries included `MoonBit 7z`, `MoonBit sevenzip`, `site:mooncakes.io/docs/ 7z`,
`aurora0x27/lzma-mbt`, and registry descriptions/names containing `7z`,
`sevenzip`, `lzma`, `bzip2` and `ppmd`. The registry was refreshed with
`moon update` on the review date. The search found the direct peer above; it
does not prove that every unpublished, unindexed or renamed implementation was
found. Recheck the named module APIs before a later submission. If reviewers
refer to another 7z package, add that exact module and revision to this table.
