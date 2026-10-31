# Install and use Moon7z 0.1.0

The module is `Wyh123456559/moon7z`; the main library packages are `archive`
and `host`. This is an initial public API release with the explicitly documented
[compatibility profile](compatibility.md), not a claim of complete 7-Zip support.

In an existing MoonBit module, run:

```console
moon add Wyh123456559/moon7z@0.1.0
```

For a separate runnable consumer, create a new directory with these three files.
No workspace member, local dependency override or checkout of Moon7z is needed.

`moon.mod`:

```moonbit
name = "local/moon7z-consumer"
version = "0.1.0"
import {
  "Wyh123456559/moon7z@0.1.0",
  "moonbitlang/async@0.22.5",
}
```

`moon.pkg`:

```moonbit
import {
  "Wyh123456559/moon7z/archive",
  "Wyh123456559/moon7z/host",
  "moonbitlang/async",
  "moonbitlang/core/env",
  "moonbitlang/core/string",
}
pkgtype(kind: "executable")
supported_targets = "+wasm+native"
```

`main.mbt`:

```moonbit
///|
async fn main {
  let args = @env.args()
  guard args.length() == 5 else {
    fail("usage: consumer ARCHIVE FILE_ID EXISTING_PARENT NEW_DIRECTORY")
  }
  let opened = @host.open_seekable_file(args[1])
  defer opened.close()
  let id = @string.parse_int(args[2])
  let checked = opened.archive.verify()
  let selected = opened.archive.reader().read_many([id])
  guard selected[0].entry.kind == @archive.File else {
    fail("select a file ID from the archive inventory")
  }
  let result = @host.export_source_selected(
    opened.archive, [id], parent=args[3], name=args[4],
  )
  println("Verified \{checked.files} files / \{checked.bytes} bytes; exported to \{result.directory}")
}
```

```console
moon update
moon check --target wasm --deny-warn
moon run --target wasm . -- /path/to/package.7z 6 /existing/parent imported
moon run --target native . -- /path/to/package.7z 6 /existing/parent imported-native
```

Supply an actual member ID from the archive inventory; `6` is only an example.
The parent must exist and be trusted, and each destination must be new. The
program verifies the whole archive before exporting selected file contents;
original metadata is returned but not applied to disk. Available CRCs detect
corruption rather than authenticity, and per-folder resource limits still apply.

The synchronous `archive` package supports Wasm, Wasm-GC, JavaScript and native.
`host`, positioned file I/O and this async consumer run on Wasm/native, including
Windows, Linux and macOS. There is no browser Promise adapter. Source/volume/SFX
lifetime, password and export policies are unchanged by registry installation.
