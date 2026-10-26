# JSON inventory and verification

Archive-level properties are retained in the additive `archive_properties`
array: UInt64 IDs are decimal strings and values are Base64 bytes, including
duplicates and empty records. See [property schema and preservation](properties.md).

Use versioned reports to index uploaded archives, select member IDs for preview,
or make a CI import decision without parsing the human-readable CLI output.
Run these commands from the checkout; no private service or 7-Zip is required:

```console
moon run app -- list --json corpus/copy-plain.7z
moon run app -- test --json corpus/copy-plain.7z
moon run app -- test --json --require-member-crcs corpus/delta-solid.7z
moon run checks/reports.mbtx -- wasm
```

The first command lists seven entries while leaving payloads unchecked. The
second decodes all members and reports four checked member CRCs and one missing
CRC (the empty file). The third enforces a CRC for every file before verifying
the two WAV files. Applying that strict command to `copy-plain.7z` refuses
`empty.txt` instead of producing a success report. `checks/reports.mbtx` verifies
parseability, repeatability, corruption handling and empty stdout on failure.
Use `-- native` on that check to execute the native CLI.

Each successful CLI command writes one compact UTF-8 JSON document and a newline.
Failures return a nonzero exit status, diagnostics on stderr and no stdout.
The flag order is `list --json PATH` or
`test --json [--require-member-crcs] PATH`. Existing text commands are unchanged.

## Inventory v1

`Archive::inventory_json() -> Json` emits `schema: "moon7z.inventory.v1"`,
`contents_verified: false` and an `entries` array. Listing is header-only, even
when the caller previously verified this immutable archive through another call.
Every call creates detached JSON arrays and objects; callers may change them
without modifying the archive or later reports.

Entries retain archive order and stable IDs, including duplicate names. Each has:

| Field | JSON representation |
| --- | --- |
| `id`, `size` | Nonnegative integer; size is the uncompressed byte count |
| `name` | Original Unicode string, JSON-escaped without path rewriting |
| `kind` | `"file"` or `"directory"` |
| `crc32` | Eight lowercase hexadecimal digits, or `null` when missing |
| `block` | Solid-folder integer ID, or `null` for an empty-stream entry |
| `metadata` | Object with every metadata field below |

Metadata fields `created_filetime`, `accessed_filetime` and `modified_filetime`
are decimal **strings** containing raw unsigned 64-bit FILETIME values (100 ns
since 1601-01-01), or `null`. `"0"`, `null` and
`"18446744073709551615"` remain distinct and round-trip without JSON number
rounding. Values are retained without converting them into calendar dates.
`attributes` is a raw unsigned 32-bit integer or `null`, exactly representable
in JavaScript. CRC presence in inventory does not mean the bytes were checked.

The library's `Entry::to_json()` and `Metadata::to_json()` use these same fields.
Inventories do not validate export paths; use `plan_contents()` before choosing
a filesystem export workflow. A name retained for inspection can still be
rejected as unsafe for export.

## Verification v1

`Verification::to_json()` emits this document for `copy-plain.7z`:

```json
{"schema":"moon7z.verification.v1","contents_verified":true,"files":5,"bytes":14550,"blocks":4,"member_crcs_checked":4,"members_without_crc":1}
```

The flag means all content was decoded and every available CRC passed, including
packed/folder checks where present. Missing member CRCs remain explicitly
counted; `true` does not imply every file has a CRC or that content is authentic.
To require all file CRCs, call `verify(require_member_crcs=true)` before creating
the report. A verification report does not record which policy the caller chose.

All counts are nonnegative integers within configured archive limits. Inventory
and report fields have fixed insertion order; arrays retain archive order, and
compact stringification is deterministic on the tested toolchain and targets.
Consumers should select fields by name, ignore unknown future fields and reject
unknown schema versions rather than depending on object key order.
