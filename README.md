# Moon7z

Read, verify and unpack 7z archives inside MoonBit applications. The library
returns complete file members and their metadata without launching 7-Zip or
writing temporary files. It is intended for importers, resource managers and
batch data tools that need to consume archives through an API.

The project is a 7z container and verified-import implementation built on an
existing LZMA/LZMA2 codec. It includes public-domain BCJ/BCJ2 adaptations; it
does not claim that the compression algorithms are original. Basic archive
reading overlaps the recently published `Sxy11112/moon7z`; the independent work
is the broader compatibility path plus bounded, verified member processing.
See [ecosystem and reuse comparison](docs/ecosystem.md), the
[versioned compatibility target](docs/compatibility.md), and
[Chinese project submission](docs/submission.md). The compatibility target is
not yet complete; passing the current tests does not imply full 7z coverage.

## Use it

```console
moon update
moon run app -- list corpus/lzma2-solid.7z
moon run app -- list --json corpus/lzma2-solid.7z
moon run app -- test corpus/lzma2-solid.7z
moon run app -- test --json corpus/lzma2-solid.7z
moon run app -- diff --json corpus/copy-plain.7z corpus/lzma2-solid.7z
moon run app -- read corpus/lzma2-solid.7z 6
moon run app -- read-range corpus/bcj-lzma2.7z 0 0 64
moon run examples/import -- corpus/lzma2-solid.7z
moon run examples/preview -- corpus/lzma2-solid.7z
moon run examples/header-scan -- corpus/lzma2-solid.7z
moon run app -- test corpus/delta-solid.7z
moon run app -- test --require-member-crcs corpus/delta-solid.7z
moon run app -- test corpus/bcj-lzma2.7z
moon run app -- test corpus/arm64-lzma2.7z
moon run app -- extract --contents-only corpus/delta-solid.7z . imported-audio
moon run app -- extract --contents-only corpus/lzma2-solid.7z . imported-package
moon run app -- extract-selected --contents-only corpus/lzma2-solid.7z . selected-manifest 6
```

The example imports the JSON manifest only after the entire archive has passed
its available CRC checks. It accepts a real archive path; the included corpus
also contains an upstream open-source project's README, license and module file.

Add `Wyh123456559/moon7z/archive` to a package's imports inside this checkout:

```moonbit
let archive = @archive.Archive::open(bytes)
for item in archive.extract_all() {
  // item.entry retains the original name, kind, CRC and optional metadata.
  // item.bytes contains the file contents; directory contents are empty.
  consume(item.entry, item.bytes)
}
```

This is an API sketch: `bytes` and `consume` belong to the application. The
module has not been published to Mooncakes. The generated interface in
[`archive/pkg.generated.mbti`](archive/pkg.generated.mbti) is the API reference.

For previews, create `let reader = archive.reader(cache_bytes=32 * 1024 * 1024)`
and call `reader.read(id)` or `reader.read_many(ids)`. IDs come from `entries()`;
duplicate names therefore remain individually addressable. Bulk reads preserve
request order and duplicate IDs, group requests by folder and check the requested
output budget before decoding. Each selected folder is decoded at most once per
bulk call, including when caching is disabled.

The reader retains at most its most recent folder within the cache budget.
Larger folders remain readable under archive limits but are not cached; zero
disables retention. `clear_cache()` releases it, and `stats()` exposes attempts,
hits and resident bytes. These counters do not establish a performance claim.
The preview example reads JSON members and then repeats a read using the cache.

For binary header previews or paged consumers, call
`reader.read_range(id, offset=0, length=64)`. It returns only the requested bytes
and does not copy the rest of the member. The entire selected folder still
decodes and passes its available CRC checks, even for a zero-length request.
This is not random access into compressed data. Offsets and lengths must be
nonnegative and fit the member; EOF permits an empty range. Out-of-bounds
requests raise `InvalidRange` before decoding and preserve an existing cache.
Directories are refused. The matching `read-range` CLI command writes binary
stdout without a newline; failures produce no content.

For multiple header/trailer fields, build `RangeRequest::new(id, offset=0, length=16)`
requests and call `reader.read_ranges(requests)`.
Results retain request order, overlaps and duplicates. All requests and combined
output bytes are checked before decoding; each selected folder is decoded at
most once per call even with caching disabled. Count and byte budgets use
`Limits.entries` and `Limits.output_bytes`. Empty ranges still check data-folder
integrity. The header-scan example reads up to 16 bytes per file without copying
full member contents; it prints only after the whole batch succeeds.

Selective reads check all available packed/folder/substream CRCs in each selected
folder, including solid siblings. **Unselected folders are not verified.** A
healthy selected file can be read while another folder is corrupt; `verify()`
still rejects the full archive. The `read` command emits exactly one file's bytes
to stdout, with no added newline. No content is emitted for an invalid ID,
directory or failed integrity check.

For disk output, `@host.export_contents(archive, parent=".", name="imported-package")`
returns the new directory and every original entry's metadata. This operation
explicitly exports **contents only**: it does not apply timestamps, permissions
or other attributes. The CLI requires `--contents-only` to acknowledge this
contract. Use the in-memory entry metadata if your application needs to store it.

Every path is planned before decoding or writing. Absolute paths, traversal,
backslashes, reserved device names, trailing dots/spaces, exact duplicates,
ASCII case aliases and file/directory conflicts are rejected. Unicode names are
preserved; exclusive creation also rejects aliases recognized by the actual
filesystem. Files are staged in a new sibling directory and published with a
no-replace rename after all checks and writes succeed. A destination that already
exists is refused, including empty directories. The caller must control the
existing parent during export; concurrent hostile modification of that parent
is outside this API's guarantees. Failed staging is removed; a cleanup failure
is returned as an I/O error and may require removing the named staging directory.

Disk export reads folders in groups and writes one owned member buffer at a
time. The reader retains at most one complete decoded folder; it does not build
an array containing all extracted member bytes. Later folder failures remove
earlier staged files before returning an error. A solid folder still decodes in
full, and input and codec buffers coexist; this is not input streaming or a
measured peak-memory guarantee. See [incremental export](docs/incremental-export.md).

To export specific resources, use
`@host.export_selected(archive, ids, parent=".", name="selected")` or the
`extract-selected --contents-only ARCHIVE PARENT NAME ID...` command. IDs come
from `entries()` or JSON inventory. Exactly those IDs are selected; a directory
ID creates that directory without recursively selecting children. Necessary
parent directories are added, and returned entries contain only selected
original metadata in request order. `archive.plan_selection(ids)` previews this
path plan. Repeated IDs and selected path collisions are refused before writing.

Selected exports check all available CRCs in their selected solid folders,
including unselected siblings. Unselected folders are not verified, so a healthy
subset can be exported despite unrelated corrupt data. Run `verify()` separately
if your ingestion policy requires whole-archive verification. The existing
no-replace staging and trusted-parent requirements apply. An empty library
selection deliberately exports an empty directory; the CLI requires at least
one ID. See [selective export workflow](docs/selective-export.md).

## Supported input

| Capability | Current behavior |
| --- | --- |
| Container | Single-volume; real fixtures cover 0.3 and 0.4; header minors 0–4 accepted; signature at byte zero |
| Codecs | Copy, LZMA, LZMA2, BZip2, raw DEFLATE, BCJ2 four-input branch reconstruction |
| Filters | Delta (distance 1–256), x86 BCJ, ARM64, ARM, ARM-Thumb, PowerPC, IA64, SPARC, Swap2/Swap4 |
| Coder graph | Bounded acyclic graphs of supported unary coders and four-input BCJ2; explicit physical input mappings |
| Headers | Plain and compressed headers |
| Members | Solid and separate folders, directories, empty files, UTF-16 names |
| Integrity | Start/next header, available packed/folder/member CRC-32 |
| Metadata | Creation/access/modification FILETIME and Windows/POSIX attribute word retained |
| Archive properties | Original ordered UInt64 IDs and opaque bytes, including duplicate IDs and empty values |
| Resources | Configurable input/header/output/dictionary/member/coder/intermediate-output limits |

Encryption, split volumes, SFX,
unlisted filters (including RISC-V), additional streams,
anti-items, links, special files, unknown semantic properties and writing are
rejected. Zero padding may repeat. The reader does not silently skip unsupported
members or metadata. Metadata values are retained for application use; the
in-memory API makes no filesystem restoration promise. Duplicate names retain
distinct IDs and archive order.

Opening checks the headers and complete member mapping. Listing does **not**
verify file contents. `verify()` and `extract_all()` decode all folders and check
all available CRCs before returning success. A missing member CRC is counted as
missing, including empty files. CRC checks detect corruption, not authenticity.

Import pipelines that require a checksum for each file can call
`archive.verify(require_member_crcs=true)` or run
`test --require-member-crcs ARCHIVE`. This refuses the first file lacking a
member CRC with `MissingChecksum(id, name)` before decoding. Empty files are
included, directories are excluded, and a shared solid-folder CRC does not
replace individual member CRCs. If every file has a CRC, all normal payload
checks still run. The default remains checking every available CRC and reporting
missing ones explicitly. This opt-in policy is a data-quality gate, not
cryptographic authentication.

For CI import gates and archive indexes, `archive.inventory_json()` returns a
fresh versioned JSON document with original entry IDs, order, names and metadata.
`archive.verify().to_json()` returns a whole-archive verification report with
explicit missing-CRC counts. `Entry`, `Metadata` and `Verification` implement
`ToJson`. Raw 64-bit FILETIME values serialize as decimal strings to preserve
precision in JavaScript consumers. Inventory never claims content verification,
and CLI failures leave stdout empty. See [JSON schema and workflow](docs/json-reports.md).

`left.compare(right)` and `diff --json LEFT RIGHT` compare fully verified
archives by exact original name. Results distinguish additions, removals, type,
content and metadata changes. Bytes are compared directly; compression, solid
layout, entry IDs and CRC presence do not create false content changes.
Duplicate names are refused as ambiguous. Output uses deterministic UTF-16
lexical name order and retains each side's original entry metadata. See
[archive comparison](docs/comparison.md) for the schema and verification scope.

`archive.properties()` retains archive-level property records as opaque data.
Inventory JSON includes their decimal-string UInt64 IDs and Base64 bytes;
comparison reports archive-property changes independently of file changes.
Properties are not interpreted or applied to disk. Unsupported file properties
remain refused. See [archive metadata preservation](docs/properties.md).

For damaged-archive triage, `archive.audit()` and `audit --json ARCHIVE` check
every data folder independently and retain typed errors while continuing past
payload failures. Reports include original entries and files lacking member
CRCs; no payload is released. A completed audit command exits successfully even
when folders fail, so consumers must inspect `all_available_checks_passed` or use
`test` for a strict exit status. Headers must still pass normal opening checks.
See [audit workflow and JSON contract](docs/audit.md).

Defaults: 64 MiB input, 4 MiB header, 128 MiB expanded data, 64 MiB dictionary,
10,000 entries, 64 coders per folder and 256 MiB summed declared coder outputs
per folder (`working_bytes`). Limits bound controlled sizes, not peak process RSS:
input, decoder buffers, folder output and returned member copies can coexist.
LZMA2 chunk sizes are checked before codec allocation. This is a bounded,
in-memory implementation, not a streaming reader or an exact backup restorer.

Whole-archive `verify()` decodes and checks one folder at a time. It does not
build the complete extracted tree or copy each member's contents; member CRCs
are checked directly on folder views. This is useful for ingestion gates that
need a report without retaining all files. A solid folder still decodes in full,
and input, packed data and codec buffers can coexist; no peak-RSS bound or
performance improvement is claimed. `extract_all()` keeps its owned-content
contract. The existing `test` and `test --json` CLI commands use this verifier.

Delta-filtered WAV/numeric data and BCJ-filtered x86 program archives use the same
verification, selective read and export APIs. Filters run over the entire solid folder before splitting
members, so history is retained across file boundaries. Coder bindings are
resolved independently of their storage order; cycles, duplicate bindings,
disconnected nodes and inconsistent length-preserving output sizes are refused
before decoding. Intermediate outputs share the folder's `working_bytes` budget;
final folder outputs share `output_bytes`. BCJ2 consumes independently mapped
main, call, jump and range-control inputs, including LZMA/LZMA2-compressed
branches. Each physical input CRC is checked before releasing folder contents.
See [BCJ2 workflow, evidence and resource policy](docs/bcj2.md).

The 7z DEFLATE method (`04 01 08`, empty properties) accepts stored, fixed and
dynamic Huffman blocks, a 32 KiB history window and overlapping matches. The
decoder checks declared output before every literal/copy and refuses trailing
compressed bytes. Existing APIs also handle Delta/DEFLATE audio archives.
See [DEFLATE import workflow and independent evidence](docs/deflate.md).

BZip2 (`04 02 02`, empty properties) supports levels 1–9, multiple blocks,
concatenated streams and legacy randomized blocks. Its block/stream CRCs are
checked alongside 7z CRCs. The data header's block size is checked against the
dictionary policy before building the inverse-transform data, and RLE expansion
is bounded by the declared coder output. See [BZip2 evidence](docs/bzip2.md).

The supported x86 BCJ method is `03 03 01 03`, with empty properties and an initial
instruction pointer of zero, as emitted by 7-Zip's BCJ coder. Nonempty properties
and the separate `04` method ID are refused. x86 here includes relative CALL/JMP
instructions in x86-64 binaries; extracting a program does not execute it.

ARM64 filtering uses method `0a`, supporting both the empty default properties
and a four-byte little-endian initial offset aligned to four bytes. Misaligned
or incorrectly sized properties are refused. BL and applicable ADRP instructions
are reconstructed over the complete solid folder, including instruction bytes
split between members; incomplete trailing bytes are retained unchanged.
The checked-in AArch64 ELF and offset/wrap archives are compared byte-for-byte
with their originals. This is archive data decoding, not execution of ARM code.

Classic ARM, ARM-Thumb, PowerPC, IA64 and SPARC methods use their registered
7z IDs with empty properties and a zero initial position. Nonempty properties
are explicitly refused, rather than interpreted as ARM64-style offsets. Swap2
and Swap4 reverse complete byte groups and preserve an incomplete final group.
Twelve independently packed archives cover these filters with Copy/LZMA2,
compressed/plain headers, a solid member boundary inside an instruction and an
odd final length. See [filter compatibility evidence](docs/filters.md).

## Validation

The checked producer matrix includes official 7-Zip 19.00, 23.01, 24.09, 25.01,
26.05 and libarchive 3.8.9: 21 required cases for Copy/LZMA/LZMA2, solid/separate
folders, plain/compressed headers and a real Unicode/empty-file source tree.
Each was independently unpacked and checked against the original bytes; fixture
SHA-256 values and software/container versions are recorded. Required cases fail
on `Unsupported` rather than being skipped. This certifies those cases, not all
features of those versions. See [producer matrix](docs/producers.md).

The core library is tested on Wasm, Wasm-GC, JavaScript and native. The host CLI
and import example use `moonbitlang/async` and support Wasm and native. CI runs
native tests and examples on Linux, macOS and Windows, and the portable targets
on Linux. Check the actual [Actions results](https://github.com/Wyh123456559/moon7z/actions)
for a particular commit rather than assuming a configured job has passed.
CI bootstraps the latest stable toolchain with MoonBit's official Unix and
PowerShell installers. It does not require a separate Nushell installation.

```console
moon run checks/verify.mbtx -- wasm
moon run checks/verify.mbtx -- wasm-gc
moon run checks/verify.mbtx -- js
moon run checks/verify.mbtx -- native
```

Tests compare every extracted byte with the uncompressed corpus, cover every
truncated prefix, repaired-envelope malformed headers, CRC corruption, numeric
boundaries, budget enforcement, deterministic output and recovery after failure.
The format reader has no writer, so archive serialization round trips are not
claimed; the relevant invariant is packing real files with 7-Zip and reproducing
the original member bytes. See [`corpus/README.md`](corpus/README.md).

## Layout and scope

`archive/` owns the portable public types and container engine; `host/` bounds
regular-file reads before allocating input; `app/` is the
host command; `examples/import/` consumes verified members; `corpus/` records
interoperability inputs; `checks/` runs repeatable verification.

Streaming, other filters, encryption and archive writing require separate
compatibility work and are not implemented.

Moon7z supplies the 7z container/member layer. Existing MoonBit LZMA/XZ codecs
and ZIP readers cover different boundaries. The compression algorithms are
reused, not presented as new inventions. See [`SOURCES.md`](SOURCES.md) for
dependency, reference and fixture licensing. Project code is Apache-2.0.
