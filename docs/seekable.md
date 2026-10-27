# UInt64 seekable input

Read metadata or a selected member without loading the entire archive. This is
useful for large asset collections, datasets delivered as split downloads and
backup verification. The source stays open while readers fetch bounded packed
folders through positioned I/O. All existing supported codecs and metadata
parsers are reused; no compression algorithm was replaced.

## Library workflow

```moonbit
let opened = @host.open_seekable_file(path)
defer opened.close()
let archive = opened.archive
let reader = archive.reader()
let member = reader.read(id)
consume(member.entry, member.bytes)
```

This sketch belongs inside an async function; the caller supplies `path`, `id`
and `consume`. `open_seekable_volumes(paths, password?, ...)` accepts the same
explicit numeric sequence rules as [bounded volume import](volumes.md). Every
part remains a separate positioned source; reads can cross any volume boundary.
No concatenated temporary file or complete in-memory archive is created.

Core users can supply `SeekableInput::new(size, read_at)`, where `read_at` has
type `async (UInt64, Int32) -> Bytes`. A callback must return exactly the requested
bytes from a stable source. Short **and oversized** results are errors. Ranges
are checked with subtraction before calling it; zero-length reads at EOF return
empty bytes without I/O. Callback exceptions, including cancellation, propagate
unchanged. `SeekableInput::concat(parts, max_parts?)` composes sources with checked
UInt64 totals and binary search over physical boundaries. Empty parts are valid
for generic composition; the file-volume loader rejects empty physical volumes.

`SourceArchive::open` reads start/next headers and any encoded/additional metadata
streams. It validates full packed-region coverage without reading main payloads.
The returned inventory retains original IDs, names, attributes, anti-items,
unknown file/archive properties and auxiliary bytes. Numeric physical positions
stay UInt64 through parsing, mapping and source reads.

`SourceArchive::reader(cache_bytes?)` supplies `read(id)` and
`read_range(id, offset~, length~)`. Each selected solid folder is decoded and all
its available pack/folder/substream CRCs checked before returning member bytes.
Only the most recent bounded folder is cached. Failed loads clear it; retries
can recover after an I/O failure. Invalid IDs/ranges are rejected before I/O or
cache changes. `clear_cache()` and `stats()` follow the ordinary Reader contract.
Use one reader serially, with separate readers for concurrent operations.
Do not close or mutate a source while operations are active.

`SourceArchive::verify(require_member_crcs?)` checks every folder one at a time.
Its `SourceVerification.bytes` is UInt64, serialized as a decimal string under
`moon7z.source_verification.v1`. Missing member CRCs remain explicit; strict
member-CRC mode refuses them before reading main payloads. CRC is not authenticity.
`inventory_json()` uses `moon7z.source_inventory.v1`, a decimal-string source
size and `contents_verified: false`, even after an earlier verification.

`host.export_source_contents` applies the same path planning, metadata refusal,
exclusive staging and no-replace publication as ordinary contents-only export.
Unsupported per-file semantics are refused before writing. A later source or
CRC failure removes staged files and publishes no destination.

## Commands and limits

```console
moon run app -- source-list --json collection.7z
moon run app -- source-test --json collection.7z
moon run app -- source-read collection.7z 7
moon run app -- source-read-range collection.7z 7 0 64
moon run app -- source-extract --contents-only collection.7z . imported
moon run app -- source-volumes-test --json package.7z.001 package.7z.002
moon run app -- source-volumes-extract --contents-only . imported package.7z.001 package.7z.002
```

`source-volumes-list --json` is also available. The existing leading
`--password-env NAME` option works with these commands. Binary read commands use
stdout for member bytes and stderr for the reminder that unselected folders were
not verified. CLI source policies use the library defaults below.

| Policy | Source API default |
| --- | --- |
| `max_source_bytes` | 1 TiB, UInt64; total of all physical parts |
| `max_output_bytes` | 16 GiB, UInt64; total declared member bytes |
| `Limits.input_bytes` | 64 MiB per packed folder/read, including all BCJ2 inputs |
| `Limits.output_bytes` | 128 MiB per decoded folder |
| Metadata/dictionary/intermediate budgets | Existing 4/64/256 MiB defaults |
| Reader cache | 32 MiB; oversize checked folders are returned without caching |
| File volumes | 1,024 by default, configurable; OS descriptor limits also apply |

The existing `Archive::open` keeps its whole-input/output bounds and synchronous
API. Source reading does not stream inside a solid folder: one folder and its
member copies still need bounded memory. A member/folder beyond that policy is
explicitly refused. Physical files use nonnegative **Int64** host positions;
custom logical inputs and composition use UInt64. File length is checked before
and after reads; this cannot establish an atomic snapshot or detect every
same-length concurrent mutation. Closing `SourceFile` closes every handle;
previously checked cached bytes and owned metadata may remain available.

The core arithmetic, composition contracts and existing synchronous engine are
checked on all four stable targets. Async source workflows currently run on
Wasm and native via the host package. No browser/JavaScript Promise adapter is
provided or claimed. Seekable SFX discovery and source-reader batch/audit/diff
convenience methods remain future work; the original in-memory APIs retain them.

## Reproducible evidence

`host/source_test.mbt` compares source reading with the in-memory engine over
the checked-in producer, codec, filter, encrypted, external-metadata and file
semantics fixtures. It covers exact bytes, all retained metadata, verification,
cache behavior, password handling, changed files, malformed read results and I/O
recovery. Numeric split fixtures include a start header crossing two seams.

`corpus/source64/` defines a valid **4,294,970,749-byte** 7z archive: 64 separate
64 MiB zero-filled Copy members followed by the existing 52-byte JSON manifest.
The start header and 3,421-byte tail reconstruct it as a sparse file. There are
no unclaimed padding gaps: the hole is declared file content. The manifest begins
at offset **4,294,967,328**. Header/member CRC coverage is recorded accurately:
the 64 zero members have no CRC, the manifest has one.

Official Linux **7zz 26.05** successfully listed and tested the entire archive and
independently extracted `manifest.json` with the exact expected bytes. Moon7z
actually read and verified this file on Linux native and Wasm. Tests also build
a virtual source with the same layout and a cross-volume seam above 4 GiB,
refusing any unexpected read of the preceding content.

```console
moon run checks/source.mbtx -- wasm
moon run checks/source.mbtx -- native
moon run corpus/source64/materialize.mbtx -- /tmp/large.7z
moon run app -- source-read /tmp/large.7z 64
```

The check needs no external archive program. It exercises listing, full
verification, binary ranges, exact filesystem export and failure cleanup. On
Linux/macOS it additionally materializes, selectively reads and verifies the
actual sparse archive; Windows uses the virtual high-offset tests and real
smaller files, avoiding a multi-GiB physical allocation. This distinction must
be preserved when reporting Windows large-file evidence. CI runs source host
tests and commands on native Linux/macOS/Windows and Wasm. Sparse large fixtures
are not checked into Git. [Sources and licenses](../SOURCES.md) apply.
