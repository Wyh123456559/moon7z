# Moon7z

Read, verify and unpack 7z archives inside MoonBit applications. The library
returns complete file members and their metadata without launching 7-Zip or
writing temporary files. It is intended for importers, resource managers and
batch data tools that need to consume archives through an API.

## Use it

```console
moon update
moon run app -- list corpus/lzma2-solid.7z
moon run app -- test corpus/lzma2-solid.7z
moon run examples/import -- corpus/lzma2-solid.7z
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

## Supported input

| Capability | Current behavior |
| --- | --- |
| Container | Single-volume 7z, version 0.0–0.4, signature at byte zero |
| Codecs | Copy, LZMA, LZMA2; one input/output coder per folder |
| Headers | Plain and compressed headers |
| Members | Solid and separate folders, directories, empty files, UTF-16 names |
| Integrity | Start/next header, available packed/folder/member CRC-32 |
| Metadata | Creation/access/modification FILETIME and Windows/POSIX attribute word retained |
| Resources | Configurable input/header/output/dictionary/member limits |

Encryption, split volumes, SFX, multiple-coder filters, additional streams,
anti-items, links, special files, unknown semantic properties and writing are
rejected. Zero padding may repeat. The reader does not silently skip unsupported
members or metadata. Metadata values are retained for application use; the
in-memory API makes no filesystem restoration promise. Duplicate names retain
distinct IDs and archive order.

Opening checks the headers and complete member mapping. Listing does **not**
verify file contents. `verify()` and `extract_all()` decode all folders and check
all available CRCs before returning success. A missing member CRC is counted as
missing, including empty files. CRC checks detect corruption, not authenticity.

Defaults: 64 MiB input, 4 MiB header, 128 MiB expanded data, 64 MiB dictionary,
10,000 entries. Limits bound individual controlled sizes, not peak process RSS:
input, decoder buffers, folder output and returned member copies can coexist.
LZMA2 chunk sizes are checked before codec allocation. This is a bounded,
in-memory implementation, not a streaming reader or an exact backup restorer.

## Validation

The core library is tested on Wasm, Wasm-GC, JavaScript and native. The host CLI
and import example use `moonbitlang/async` and support Wasm and native. CI runs
native tests and examples on Linux, macOS and Windows, and the portable targets
on Linux. Check the actual [Actions results](https://github.com/Wyh123456559/moon7z/actions)
for a particular commit rather than assuming a configured job has passed.

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

Next capabilities are a destination-safe file exporter and selective member
access with solid-block reuse. Streaming, more filters and encryption require
separate compatibility work and are not implemented.

Moon7z supplies the 7z container/member layer. Existing MoonBit LZMA/XZ codecs
and ZIP readers cover different boundaries. The compression algorithms are
reused, not presented as new inventions. See [`SOURCES.md`](SOURCES.md) for
dependency, reference and fixture licensing. Project code is Apache-2.0.
