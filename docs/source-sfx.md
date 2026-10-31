# Seekable SFX and embedded archives

`SourceEmbeddedArchive` extends SFX import to positioned UInt64 input, including
numeric split volumes. Inspect installers, verify embedded packages and import
resources without executing the stub or loading the complete input into memory.
The ordinary [in-memory SFX API](sfx.md) retains its API and JSON schema.

## Library workflow

```moonbit
let opened = @host.open_seekable_sfx_file(path)
defer opened.close()
let imported = opened.embedded
let checked = imported.archive.verify()
let reader = imported.archive.reader()
consume(checked, reader.read(id))
```

This sketch belongs inside an async function. The caller supplies `path`, `id`
and `consume`. Use `open_seekable_sfx_volumes(paths, ...)` for an explicit numeric
sequence. Its naming, part-count and missing/reordered-volume rules match
[ordinary split sources](volumes.md). A signature/header, packed folder or
opaque footer may cross any physical part boundary.

Core integrations call `SourceEmbeddedArchive::open(source, ...)`, or
`open_at(source, offset, ...)` when an index already supplies the UInt64 offset.
The returned fields `prefix`, `payload` and `suffix` are exact live
`SeekableInput` views. Recompose them with `SeekableInput::concat` to recover the
entire original input; `slice(offset, size)` creates other checked views without
reading their contents. All views share the source lifetime and stability
requirements. Closing the host handle closes all underlying files.

The embedded `archive` is the normal `SourceArchive`: retained metadata, cached
ID/range reads, full verification, strict member-CRC policy and conservative
contents-only export all apply. Prefix/configuration/trailer bytes are not run,
interpreted as trusted executable data or authenticated. Export explicitly
applies only the archive's safe contents and never rewrites the original input.

## Discovery and policies

The default candidate-start bound is **1 MiB**, with UInt64 `search_bytes`.
Candidates are in `0..<search_bytes`; their complete 32-byte header may extend
past that boundary. Discovery uses windows of at most **64 KiB**, also capped by
`Limits.input_bytes`, with 31 bytes of lookahead. It may therefore read a small
portion of archive content while searching. It never buffers the entire prefix,
and a known offset bypasses prefix scanning.

Bad start-header CRC decoys are skipped. The **first CRC-valid complete header**
is selected: unknown version, invalid extent, bad metadata, unsupported method
or missing/wrong password errors return immediately. No later healthy archive
hides such a failure. Source I/O exceptions propagate and scans may be retried.
`SourceSignatureNotFound` reports the actual eligible positions searched as a
UInt64, including zero; its JSON field is a decimal string.

UInt64 extent/view additions are checked before constructing a payload view.
Truncated input, overflow and invalid explicit offsets are rejected. The normal
[seekable source policies](seekable.md) apply: the default 1 TiB source cap
includes the entire envelope, the 16 GiB declared-output cap applies to embedded
members, and per-folder/read/header/dictionary limits remain explicit. The host
`offset?` option bypasses discovery; `search_bytes` applies when it is absent.

`inventory_json()` emits `moon7z.source_embedded_inventory.v1`, decimal-string
source/offset/prefix/archive/suffix sizes, and the decoded archive inventory.
It is a **layout report**, not an envelope serialization: raw bytes remain in
the live views, `envelope_bytes_included` is false, and the original source is
needed to read them. `contents_verified` and `envelope_verified` remain false.
The test CLI emits `moon7z.source_embedded_verification.v1` with a nested archive
verification report; its CRC checks do not authenticate the envelope.

## Commands and runnable evidence

```console
moon run app -- source-sfx-list --json installer.exe
moon run app -- source-sfx-test --json installer.exe
moon run app -- source-sfx-test --offset 35328 --json installer.exe
moon run app -- source-sfx-list --scan-bytes 2097152 --json installer.exe
moon run app -- source-sfx-read installer.exe 0
moon run app -- source-sfx-read-range installer.exe 0 0 64
moon run app -- source-sfx-extract --contents-only installer.exe . resources
moon run app -- source-sfx-volumes-test --json bundle.7z.001 bundle.7z.002
moon run app -- source-sfx-volumes-extract --contents-only . resources bundle.7z.001 bundle.7z.002
```

`source-sfx-volumes-list --json` is also supported. An optional `--offset` or
`--scan-bytes` immediately follows the command; both together are refused.
Leading `--password-env NAME` works for encrypted SFX. Binary reads use stdout
for exact member bytes and stderr for the verification-scope reminder.

```console
moon run checks/source-sfx.mbtx -- wasm
moon run checks/source-sfx.mbtx -- native
moon run corpus/sfx/materialize-large.mbtx -- /new/large-sfx.bin
moon run app -- source-sfx-read /new/large-sfx.bin 64
```

The checks reuse the three Public Domain SDK 26.05 GUI/console/installer stubs
and attributed package files from [the SFX corpus](../corpus/sfx/manifest.md).
They exercise inventory, explicit-offset verification, exact export, binary
stdout, split headers/footers, unchanged originals, malformed CLI arguments,
scan refusal and corrupted-export cleanup. Unit tests add window boundaries,
32-byte read budgets, invalid/truncated/overflowing inputs, password and I/O
recovery, views above 4 GiB and view use after closing the file.

On Linux/macOS the check also materializes a **4,295,006,092-byte** sparse SFX:
the unchanged 35,328-byte SDK GUI stub, the existing 4,294,970,749-byte source64
archive, and a 15-byte opaque footer. It actually reads the member beyond 4 GiB
and verifies all available archive CRCs. Its 64 zero-filled members have no CRCs;
the JSON member has one. On Linux, official **7zz 26.05** reported the same
35,328-byte offset, archive extent, 65 members and 15-byte tail, checked the
archive and independently extracted the exact JSON. It also reported the
expected **data-after-end warning** for that opaque footer; this is not claimed
as warning-free interoperability or validation of the trailer. The executable
stub was never run. The Linux test file occupied 44 KiB; other filesystems may
allocate differently.

Windows runs real smaller SFX and virtual UInt64 offset tests; sparse large-file
materialization is restricted to Linux/macOS. Core numeric/discovery tests and
existing portable functionality run on all four stable targets; async host
workflows run on Wasm and native Linux/macOS/Windows. No browser adapter or
arbitrary executable-format validation is claimed. Registry installation and
independent consumer reproduction are covered by the [installation guide](install.md).
