# Compare package contents across archives

## Positioned files, volumes and SFX

`left.compare(right, require_member_crcs?)` on two `SourceArchive` values returns
`SourceComparison`. Files, numeric volumes and embedded SFX use the same API and
may be compared across input types. Open each side with its own password when
needed. Both sources must remain stable and open throughout the operation.

The report uses `moon7z.source_comparison.v1`, the same six `ChangeKind` values
and original metadata/property records as in-memory comparison, and UInt64
verification totals serialized as decimal strings. Duplicate names fail before
main-payload I/O. Both archives are fully verified before comparing, including
added/removed members; errors propagate without returning a partial report.
The optional strict policy requires individual CRCs, including for empty files.

Files compare actual bytes using at most 64 KiB returned copies per side.
Two internal readers each retain at most one decoded folder, sized up to that
archive's existing per-folder limit. Packed/decoder buffers coexist with these
caches; no measured peak-memory or speed claim is made. This does not stream
within a compressed solid folder. Verification and later comparisons may decode
folders again. Large input size does not bypass per-folder resource limits.

```console
moon run app -- source-diff --json corpus/copy-plain.7z corpus/lzma2-solid.7z
moon run app -- source-sfx-diff --json old-installer.exe new-installer.exe
moon run checks/source-compare.mbtx -- wasm
moon run checks/source-compare.mbtx -- native
```

The CLI exits zero for a complete equal or different report; inspect `identical`.
Opening, source I/O, decryption or integrity failures exit nonzero with empty
stdout. `scope: decoded_archive_contents_and_metadata` explicitly excludes SFX
prefix/config/trailer bytes and volume layout; it is not executable equality or
authenticity. Missing CRCs remain visible, and same-length concurrent source
mutation cannot be ruled out by this API. Existing synchronous comparison is
unchanged. The end-to-end check compares real differently packed archives and
official SDK GUI/console SFX, then refuses a damaged archive with removed data.

## In-memory archives

Use a verified content comparison when updating resource packs or checking a
repacked distribution. Both archives must have unique original member names.
No extraction directory or private service is needed:

```console
moon run app -- diff --json corpus/copy-plain.7z corpus/lzma2-solid.7z
moon run app -- diff --json corpus/binary.7z corpus/arm64-lzma2.7z
moon run checks/compare.mbtx -- wasm
```

The first comparison is identical despite different codecs and solid layout.
The second reports removal of `payload.bin` and addition of `program.elf`.
The check also damages a payload and asserts a nonzero exit with empty stdout.
Use `-- native` on the check to execute the native CLI.

Call `left.compare(right)` to obtain a `Comparison`. `identical()` describes
member names, kinds, bytes and metadata; `changes()` returns a detached array.
Retained archive properties and raw additional metadata streams also contribute
to `identical()`. `metadata_streams_changed()` and the JSON fields
`metadata_streams_changed`, `left_metadata_streams`, `right_metadata_streams`
report the latter independently. Inline versus external storage may therefore
have identical file values and no entry changes but different retained raw
metadata; see [external metadata comparison](external.md).
`to_json()` emits `moon7z.comparison.v1`, with `identical`, `left_verification`,
`right_verification` and `changes`. Each change contains its exact `name`,
`kind`, and original `left` / `right` entry documents (absent sides are `null`).

Kinds are `added`, `removed`, `type_changed`, `content_changed`,
`metadata_changed` and `content_and_metadata_changed`. File contents are compared
byte-for-byte after both archives pass all available CRC checks; neither sizes
nor matching CRCs substitute for byte comparison. Retained timestamps and raw
attributes are metadata. Missing metadata and numeric zero remain distinct.
Start positions are metadata too. Anti-flag or interpreted filesystem-type
changes produce `type_changed`, even when the entry name and bytes match.
Entry IDs, compression, solid blocks and presence/absence of member CRCs do not
define content equality; the two verification reports retain missing-CRC counts.

Names are exact and case-sensitive, without path or Unicode normalization.
Changes sort lexically by UTF-16 units. A repeated original name on either side
raises `AmbiguousName` with its first two IDs; comparison does not silently
choose one entry. Inspection/comparison preserves names that may be unsafe for
filesystem export; use an export plan before writing them to disk.

Both archives are verified even when they have no names in common. A successful
report never hides corrupt added/removed files. CRC checks detect corruption,
not authenticity. To require CRCs for every file, verify both archives with
`require_member_crcs=true` before comparing. The comparison may decode folders
again to compare bytes and uses the existing reader cache policy; no streaming,
peak-memory or performance claim is made. A successful CLI comparison exits zero
whether equal or different; inspect `identical` in JSON. Failures emit no stdout.

Archive-level properties are compared separately from member changes. Reports
include `archive_properties_changed` and both original property arrays. When only
those records differ, `changes` is empty but `identical` is false. See
[archive properties](properties.md) for the lossless representation.

Unrecognized file-table properties are also compared in original order, including
duplicate IDs and empty values. `file_properties_changed()` and JSON
`file_properties_changed`, `left_file_properties`, `right_file_properties`
preserve their differences separately. If only those records differ, `changes`
is empty and `identical` is false. IDs are decimal strings and bytes are Base64;
this does not claim that their unknown per-entry semantics have been decoded.
