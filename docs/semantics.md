# Inspect file semantics before importing contents

An archive can describe links, special files or deletion markers as well as
ordinary contents. Moon7z retains these descriptions as data. It never creates
links/devices, follows a reparse point or applies an anti-item deletion.

## A complete workflow

```console
moon run app -- list --json corpus/semantics/mixed.7z
moon run app -- read corpus/semantics/mixed.7z 1
moon run app -- extract-selected --contents-only corpus/semantics/mixed.7z . imported-manifest 0
moon run app -- diff --json corpus/semantics/extended.7z corpus/semantics/changed.7z
moon run checks/semantics.mbtx -- wasm
moon run checks/semantics.mbtx -- native
```

The inventory has six original entries: a 52-byte JSON manifest, a symbolic link
whose 13 target bytes are `manifest.json`, an empty FIFO, two anti-items (file and
directory), and a directory reparse point. ID 0 can be explicitly exported into
a new directory. Selecting a link, FIFO, anti-item or reparse point fails before
writing. Reading ID 1 returns the target text as bytes; it does not follow it.
The check uses a temporary trusted parent, keeps an existing deletion-target
sentinel unchanged and verifies that refused exports leave no staging output.
It also exports regular/positioned entries and compares their original bytes.
The native command runs the native CLI, rather than only compiling it.

## Public contract

- `Entry.anti` retains the Anti mask for empty-stream entries. `Entry.kind`
  still distinguishes a file entry from a directory entry.
- `Entry::semantics()` returns `Regular`, `SymbolicLink`, `ReparsePoint` or
  `Special`. POSIX file types require the Unix-extension attribute flag
  `0x8000`; the high word alone is not enough. Raw attributes remain available.
- `Metadata.start_position` retains an optional UInt64 byte position, including
  zero and the maximum value. Contents-only export does not apply it.
- `Archive::file_properties()` returns a detached array of unrecognized
  FilesInfo records, preserving original order, repeated UInt64 IDs, empty values
  and all bytes. It does not claim to interpret them per entry. Because their
  semantics could affect any entry, all **nonempty** export selections from such
  an archive are refused. Applications can inspect the records and read bytes
  through their own explicit import policy. Empty selections remain valid.
- `Limits.file_property_records` bounds all FilesInfo property records,
  independently of the entry-count budget. Its default is 10,000.

Inventory JSON adds `anti`, `semantics`, decimal-string/null `start_position`
and `file_properties` records with decimal-string IDs and Base64 data. Comparison
classifies anti/type differences as `type_changed`, start positions as metadata,
and opaque-record differences independently through `file_properties_changed()`.
It retains both original record arrays. Unknown bytes are not silently dropped
or assigned invented meanings. Repeated known properties, malformed masks/lengths
and truncated UInt64 IDs are refused. Tests also check recovery, deterministic
JSON, UInt64 precision and detached arrays.

`verify()`/`audit()` count file entries, including anti-files and special files;
they do not count successfully restored regular files. For `mixed.7z` the byte
sum is 65, with two checked member CRCs and two explicitly missing member CRCs.
CRC checks do not prove authenticity or safe restoration.

## Fixture provenance and independent checks

All five containers and `corpus/semantics/generate.mbtx` are project-authored
Apache-2.0 data/code. They use the existing 52-byte `corpus/source/清单.json`,
project-authored link text and synthetic attributes/positions. No external test
suite or archive was copied. Container/Anti/StartPos rules were cross-checked
with official 7-Zip 26.05 `7zIn.cpp`; no C++ code was copied.
The Unix-extension flag was checked against the same version's
[FileFind.cpp](https://github.com/ip7z/7zip/blob/26.05/CPP/Windows/FileFind.cpp)
and [FileDir.cpp](https://github.com/ip7z/7zip/blob/26.05/CPP/Windows/FileDir.cpp).

Regenerate to a **new** directory using official 7-Zip Extra 26.05:

```console
moon run corpus/semantics/generate.mbtx -- PATH_TO_7ZA NEW_OUTPUT_DIRECTORY
```

The generator runs independent `7za t` and `7za l -slt` on all five. Exit status
is zero; the unknown-property cases also report **Unsupported feature** warnings.
The mixed listing independently identifies the link, FIFO, both anti-items and
reparse-point attributes. Only `safe.7z` is independently extracted and compared
to its original. 7-Zip refuses restoration of the StartPos/unknown-property cases;
mixed special entries are not independently restored. Those limitations are
not counted as successful independent extraction. Moon7z compares readable
payloads and preserved metadata against the construction inputs on all targets.

| Fixture | SHA-256 |
| --- | --- |
| `safe.7z` | `d65aeba43a73b4199e75358524da7c8c0703d41c038ec37c8718cf6b31e60d4d` |
| `position.7z` | `5a5ab2b579689b84787d163459050b7fcd14190244719534f4f803a2e656ebd2` |
| `extended.7z` | `c70b2460da4accbde95df4bd980c0d5c7a6d916489d5953eb041e407461bee48` |
| `changed.7z` | `5f7777bd3fd67c20475d27cd8448c432205cfa3c78d67e5b3b8e67bf3b73cb57` |
| `mixed.7z` | `75b192e6ed12e7439e1d69561874cf5bf216bc0710048c9147f7bbba07f87d3b` |

This is file-semantic reading, not a general filesystem-restoration engine. The
remaining common-reader requirements are tracked in [compatibility.md](compatibility.md).
