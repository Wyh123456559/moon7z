# External metadata and header placement

7z producers can move names, timestamps, attributes or folder definitions into
additional packed streams. Moon7z resolves those references during opening,
checks every available physical/folder/substream CRC, then exposes the same
member APIs and contents-only export workflow as inline metadata.

```console
moon run app -- list --json corpus/external/external.7z
moon run app -- extract --contents-only corpus/external/encoded-first.7z out metadata-import
moon run app -- diff --json corpus/external/external.7z corpus/external/changed.7z
moon run checks/external.mbtx -- wasm
moon run checks/external.mbtx -- native
```

Create `out` first and use a new destination. The checker compares the exported
`清单.json` with `corpus/source/清单.json`, checks retained stream data in inventory
JSON and verifies that an opaque metadata change is reported without inventing
a file-content change. Native mode executes the native CLI.

## Preservation and correctness

`archive.metadata_streams()` returns a detached array of immutable decoded
buffers in additional-folder order. Reference indices address this array;
they do not index solid substreams. Referenced and unreferenced buffers are both
retained. Inventory JSON adds `metadata_streams`, an array of integer `id` and
Base64 `data_base64` records. JSON serialization/parsing preserves all bytes.

`comparison.metadata_streams_changed()` compares these original buffers;
comparison JSON adds that flag and `left_metadata_streams` /
`right_metadata_streams`. File changes continue to compare decoded members and
interpreted metadata. Moving identical values between inline and external
storage therefore leaves `changes` empty but conservatively makes `identical()`
false because retained raw metadata differs. Compression changes with identical
decoded metadata buffers do not create this difference.

External flags, UInt64 indices, counts, UTF-16 terminators, defined-value masks
and complete typed-buffer consumption are validated. Invalid references and
truncation are typed input errors, rather than guessed values. Opening decodes
metadata, including unused buffers, so a bad metadata CRC fails even when a
caller only wants a listing. File payloads remain verified by read/verify/audit.

Encoded headers may have one decoded folder containing multiple substreams;
all substream CRCs are checked. Multiple decoded encoded-header folders are
invalid under the referenced official reader mapping. An encoded header with no
folders represents an empty inventory. Main/additional data can occur before or
after encoded-header bytes. All packed regions must fit before the next-header
descriptor, be disjoint and cover the body without gaps; unclaimed input is
explicitly refused. Input bytes are not silently discarded.

`header_bytes` bounds the next-header descriptor and decoded header. The decoded
header and additional-stream outputs also share that decoded-byte budget;
graph working and dictionary limits remain independent. This is not a peak-RSS
or streaming guarantee. Opening encrypted metadata uses the same password and
cumulative key-derivation budget as the other encrypted paths.

## Independently validated fixtures

These five containers are project-authored from official format mappings,
using the existing Apache-2.0 JSON payload and synthetic valid FILETIMEs. Official
7-Zip Extra 26.05 independently tested and extracted each, matching every payload
byte. They are not copied archives or external test cases.

| Case | Structure | SHA-256 |
| --- | --- | --- |
| external | Seven additional folders; external name, three times, attributes and main folder; unused opaque bytes | `1abdcbd7ac065f88b78a888d31cb9dc1146ff0424cde27bfca72398a651836b0` |
| changed | Same members, changed unused metadata buffer | `e8e904841cb2018761d7b9f63860ae549b41188a0e69090e386b190e9309599e` |
| encoded-first | Copy-encoded header physically before main/additional data | `f6ea8ccd89fd5097f9451b9a8cb9564204da14e2b2a3dd101affe8eb47c20461` |
| encoded-pieces | Same placement, two encoded-header substreams | `c0a347a79cf9f8384209d704cbdb0c9322b680851fea6026dd3ff9329aa28a1e` |
| inline | Equivalent file values stored inline, no additional streams | `962d15174a09f7baef1d6f38d3b55471c4a6f17b59c7b015cbccbabd4ff4bb73` |

```console
moon run corpus/external/generate.mbtx -- PATH_TO_7ZA26 NEW_DIRECTORY
```

The builder uses valid nine-byte UInt64 encodings to keep header positions
stable while moving packed regions. Tests also cover missing/out-of-range
references, malformed flags, aggregate limits, overlaps/gaps, unused-buffer CRC
failure, deterministic output and retry after failure. Mapping references and
licensing are in [SOURCES.md](../SOURCES.md). The wider
[compatibility target](compatibility.md) still requires the remaining codecs,
file semantics and input-source work.
