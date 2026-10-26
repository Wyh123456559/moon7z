# Preserve archive properties without applying them

7z Header section `ArchiveProperties` contains typed, length-delimited records.
Moon7z retains each record's original UInt64 ID and immutable value bytes in
archive order, including repeated IDs, empty values and bytes that are not text.
The public `Archive::properties()` returns a fresh array of read-only
`ArchiveProperty` records. Clearing that array cannot modify the archive.

The reader uses the standard 7z variable UInt64 representation for property
IDs, matching the official reader's `ReadID` behavior. The high-level text's
`BYTE PropertyType` notation does not justify reading high IDs as one byte:
the checked fixture uses IDs 128 and 255 and was independently accepted by 7zr.
Tests also preserve the UInt64 maximum, reject malformed/truncated fields and
bound both header bytes and property record count. Record count uses
`Limits.entries`, reported separately as an `archive property records` limit.

Inventory's `moon7z.inventory.v1` document now includes an additive
`archive_properties` array:

```json
{"id":"128","data_base64":"AP9BCg=="}
```

IDs are decimal strings to preserve UInt64 precision in JavaScript; data uses
standard Base64, preserving zero bytes and non-UTF-8 data. Missing properties are
an empty array. Decode the Base64 to recover the exact bytes. JSON round-trip,
Base64 restoration and deterministic ordering are tested. Readers of versioned
reports should tolerate additive fields; existing entry IDs remain numbers.

Comparison includes `archive_properties_changed`, `left_archive_properties`
and `right_archive_properties`. `Comparison::identical()` is false when only
archive properties differ, even if `changes()` is empty. File-change ordering
and original metadata remain unchanged. Comparison is conservative: original
property ordering and duplicate occurrence changes are observable.

These values are opaque metadata, not trusted instructions. They are never
executed, interpreted as file paths, or applied during contents-only export.
This does not relax refusal of unsupported file properties, encryption or
additional streams. Keep inventory/property data alongside exported contents
when an application needs the original archive-level metadata.

```console
moon run app -- list --json corpus/properties/properties.7z
moon run app -- diff --json corpus/copy-plain.7z corpus/properties/properties.7z
moon run checks/properties.mbtx -- wasm
moon run checks/properties.mbtx -- native
```

The fixture adds three project-authored property records to the existing real
Copy corpus, repairs the envelope CRCs, and is accepted and unpacked by 7zr
26.04 to the original five files. It is not produced by a public Moon7z writer.
To regenerate into a new directory, from the repository root:

```console
moon run corpus/properties/generate.mbtx -- /path/to/7zr /tmp/new-properties-corpus
```

The generator runs independent validation/extraction and compares file bytes.
Normal tests and runtime use do not require the packer.
