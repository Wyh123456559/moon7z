# Numeric 7z split volumes

Moon7z reads explicit ordered sets such as `backup.7z.001` / `.002` / `.003`.
Use this to import multi-download datasets, verify a copied backup before
restoration, or inspect a split resource package without shell concatenation or
installing 7-Zip. The same entry-ID reads, audit, comparison and conservative
contents-only export apply after opening.

## Library and CLI

```moonbit
let sequence = @archive.VolumeSequence::new(["assets.7z.001", "assets.7z.002"])
let split = sequence.open([first_bytes, second_bytes])
let report = split.archive.verify()
consume(report, split.volumes(), split.archive.reader())
```

This is an API sketch: the caller supplies bytes and `consume`. Host applications
use `@host.open_volume_files(paths, limits?, password?, max_volumes?)`. It checks
all names, opens only regular files, preflights every size and the cumulative
budget before reading data, then checks for length changes. Handles close on
every exit path. Inputs must be complete and stable: this is not an atomic
snapshot and cannot detect every same-length concurrent change.

```console
moon run app -- volumes-list --json backup.7z.001 backup.7z.002 backup.7z.003
moon run app -- volumes-test --json backup.7z.001 backup.7z.002 backup.7z.003
moon run app -- volumes-extract --contents-only . restored backup.7z.001 backup.7z.002 backup.7z.003
moon run app -- --password-env ARCHIVE_PASSWORD volumes-test --json secret.7z.001 secret.7z.002
```

Provide every part explicitly and in numeric order. There is no sorting,
directory discovery or guessing which similarly named files to append.
`VolumeSequence::new` validates labels independently of payloads, so downloaders
can reject a bad list before fetching its contents. Labels are single filenames;
the host API accepts paths and derives their filename labels.

Numeric suffixes have 2–10 digits, begin at zero or one and retain their initial
zero padding until a natural carry (`.999` to `.1000`). Names are compared
exactly. Duplicate, reordered, skipped or mixed-set names produce a typed
`VolumeError` with a zero-based list index and corrective reason. Missing final
parts and truncated combined inputs have a separate extent diagnostic. Empty
parts, count mismatch and extra trailing bytes are refused. Parts may have
different sizes and may split any header or packed stream.

The default maximum is **1,024 parts** and **64 MiB combined input**. The count
policy is configurable; the existing controlled in-memory maximum remains
`0x3fffffff` bytes. The implementation checks the total before assembling one
owned archive buffer. It also retains the part buffers during assembly, so this
is not constant-memory or seekable large-file reading. OS descriptor limits can
also refuse large part counts. UInt64 offsets in `VolumeInfo` describe layout;
they do not imply that archives larger than the input budget are supported.

`SplitArchive::inventory_json` emits `moon7z.split_inventory.v1`, the ordered
part names/sizes/decimal-string offsets and an ordinary archive inventory.
Its `contents_verified` flag remains false. The test CLI emits
`moon7z.split_verification.v1` with a nested ordinary verification report.
CRC coverage is unchanged: names do not authenticate contents and renamed or
substituted parts are only caught where structural checks or available CRCs
detect the alteration. There is no independent checksum in a plain split part.

GNU-style alphabetic `.aa` sets, split SFX envelopes, self-discovery from a first
part and recovery of unfinished archives with an empty StartHeader are outside
this API. These are explicit scope limits; no part or unsupported bytes are
silently skipped. Ordinary `Archive::open` and file opening keep their behavior.

## Reproducible evidence

Official **7za 26.05** generated, tested and independently unpacked these sets:

| Case | Method | Part sizes | Total bytes |
| --- | --- | --- | ---: |
| fixed | LZMA2, solid | 2048 / 2048 / 1454 | 5550 |
| variable | Copy | 13 / 23 / 4096 / 4096 / 4096 / 2074 | 14398 |
| encrypted | LZMA2, AES data and header | 2048 / 2048 / 1519 | 5615 |

The variable case splits the 32-byte start header twice. All three extracted
files were compared byte for byte with the original attributed README/LICENSE
and project JSON manifest (14,229 bytes). The per-part SHA-256 values are in
[`corpus/volumes/manifest.json`](../corpus/volumes/manifest.json); the public test
password is `moon7z-volumes`. AES regeneration changes salts/IVs and therefore
encrypted part hashes. Neither 7-Zip nor private infrastructure is needed to
run the checked-in examples:

```console
moon run checks/volumes.mbtx -- wasm
moon run checks/volumes.mbtx -- native
moon run corpus/volumes/generate.mbtx -- /path/to/7za /new/output
```

The first two commands verify fixture hashes, list/test/extract every set,
compare original bytes, preserve source files and check that invalid sequences,
missing tails and a damaged payload publish no output. Portable tests cover
every boundary in and around the start header, numbering carries, limits,
password recovery, deterministic JSON and ordinary archive comparisons. Host
tests cover missing, empty, nonregular and oversized files followed by recovery.
CI executes these workflows on Wasm and native Linux/macOS/Windows and the core
tests on Wasm-GC and JavaScript. Source/license details are in [SOURCES.md](../SOURCES.md).

The separate [seekable source API](seekable.md) now composes numeric volumes
without joining them in memory. Mooncakes publication remains unfinished.
