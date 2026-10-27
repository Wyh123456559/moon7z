# Reconstructible UInt64 source fixture

Project-authored Apache-2.0 framing and generator. The final member is the
existing attributed JSON from `corpus/source/清单.json`; preceding members contain
only NUL bytes, generated as sparse-file holes. No external program or fixture
content is included. The exact generated layout is in `manifest.json`.

| Stored fragment | Bytes | SHA-256 |
| --- | ---: | --- |
| start.bin | 32 | 3f6bc0ef0533b4aa1ac3c5481af70fc7408cc9e5ab33e57fd5c3e52404d5b5f7 |
| tail.bin | 3421 | 2ca81fa0a25005afbb1a61f4f900c300862cb4d1e7178044f154679fb282873f |

```console
moon run corpus/source64/generate.mbtx -- /new/fragment-directory
moon run corpus/source64/materialize.mbtx -- /new/large.7z
7zz l /new/large.7z
7zz t /new/large.7z
7zz x -so /new/large.7z manifest.json
```

Materialization requires Linux/macOS sparse-file behavior and creates a new
file without replacing an existing one. On 2026-10-27 the 4,294,970,749-byte file
occupied 8 KiB in the Linux test filesystem. That allocation is an observation,
not a promise about other filesystems. Official 7zz 26.05 reported 65 Copy blocks,
65 files and 4,294,967,348 decoded bytes; `t` passed and the selected JSON matched
its original. The 64 zero members lack CRCs, explicitly reported by Moon7z.

The development oracle came from the official
[Linux 26.05 release asset](https://github.com/ip7z/7zip/releases/download/26.05/7z2605-linux-x64.tar.xz),
SHA-256 `22cf82fcc6eb7474f1d5bb4f02c0f8ebd573a718089d6833dc30f8350a3b232e`.
This LGPL/BSD-containing binary was used only for validation, is not distributed
here and is not used by Moon7z. See [seekable workflow](../../docs/seekable.md).
