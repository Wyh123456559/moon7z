# Auditing damaged archives

## Positioned files, volumes and SFX

`SourceArchive::audit()` now supplies the same `AuditReport` and `moon7z.audit.v1`
schema through bounded UInt64 positioned reads. Ordinary files, numeric volumes
and the archive inside a `SourceEmbeddedArchive` use this method. It never loads
the full source or accumulates decoded folders. Typed `ArchiveError` failures
are recorded per folder; arbitrary source I/O exceptions propagate unchanged,
so a caller can repair the source and retry. Cancellation is not swallowed.
Invalid headers still prevent opening. A complete report may contain failed
folders; inspect its status rather than treating CLI exit zero as integrity.

```console
moon run app -- source-audit --json corpus/copy-plain.7z
moon run app -- source-volumes-audit --json part.001 part.002
moon run app -- source-sfx-audit --json installer.exe
moon run app -- source-sfx-volumes-audit --json installer.001 installer.002
```

SFX commands also accept the existing `--offset`/`--scan-bytes` and leading
`--password-env` options. Their `moon7z.source_embedded_audit.v1` layout wraps
the audit with exact decimal-string offsets/sizes and `envelope_verified: false`.
The stub and suffix are never executed or authenticated. Missing CRCs remain
explicit. These host workflows run on Wasm and native Linux/macOS/Windows.

## In-memory archives

Use `archive.audit()` when an archive ingestion service needs to identify every
damaged data folder rather than stop at the first payload failure. Opening the
archive must still succeed: malformed headers, unsupported codecs and unsafe
resource declarations are refused by `Archive.open` before auditing.

```console
moon run --target wasm app -- audit --json corpus/copy-plain.7z
moon run checks/audit.mbtx -- wasm
moon run checks/audit.mbtx -- native
```

The end-to-end check corrupts a real archive's first packed folder, checks its
typed checksum diagnostic and confirms that later folders still pass. It also
checks that the strict `test` command rejects the same archive and that malformed
headers produce no JSON on stdout. It creates and removes its own temporary data.

The `moon7z.audit.v1` JSON document contains:

| Field | Meaning |
| --- | --- |
| `all_available_checks_passed` | Every folder passed decoding and all available CRC checks |
| `folders` | Folder ID, declared expanded bytes, original entries, status and nullable error |
| `entries_without_data` | Original entries with no data folder, including directories and empty files |
| `files_without_crc` | Original files without individual CRCs, including empty files |

Folders are checked independently in archive order. A folder failure does not
prevent checking later folders; a solid folder is the unit of isolation, so its
individual files cannot be certified when the folder fails. No payload is
returned or exported. Entries retain original IDs and metadata, and report
collection accessors return fresh arrays. Repeated audits are deterministic.

`ArchiveError` implements `ToJson` with a stable `code`, human-readable `message`
and variant-specific fields. For example, a checksum error includes `scope`, and
an invalid range includes `id`, `offset`, `length` and `size`. Consumers should
branch on `code`, not parse the message. JSON uses the serializer's normal string
escaping; original metadata uses the same representation as inventory reports.

The CLI exits successfully when it has produced a complete audit report, even
if some folders failed. Automation must inspect `all_available_checks_passed`;
use `test` or `test --require-member-crcs` for a failing process status on an
integrity-policy violation. Opening and I/O failures still exit unsuccessfully
with empty stdout.

Missing CRCs remain explicitly listed and do not themselves fail this available
checks audit. A passing report is neither proof of authenticity nor a promise
that every member had its own checksum. No corrupted content recovery is
attempted. Input and decoder buffers remain subject to the existing archive
limits; auditing releases each decoded folder before moving to the next.
