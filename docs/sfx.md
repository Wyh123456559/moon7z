# SFX and embedded 7z import

Applications can inspect an installer bundle, import its resources or compare its
contents with a plain archive without running the executable stub. This is an
owned, bounded in-memory API. It does not interpret installer instructions,
validate an executable or authenticate a signature.

## Public workflow

```moonbit
let embedded = @archive.EmbeddedArchive::open(input)
// Or use open_at(input, offset) when an upstream index supplies the offset.
let report = embedded.archive.verify()
let reader = embedded.archive.reader()
consume(report, reader)
assert_eq(embedded.prefix + embedded.payload + embedded.suffix, input)
```

This is an API sketch; the caller supplies `input` and `consume`. Existing
entry-ID/range/batch/audit/compare/export workflows use `embedded.archive`.
The host API `@host.open_embedded_file(path, password?, search_bytes~)` checks
regular-file size before allocating. Both APIs accept the existing `Limits`
policy. Ordinary `Archive::open` and `host.open_file` still require a signature
at zero and reject trailing bytes. SFX discovery is deliberately explicit.

```console
moon run app -- sfx-list --json installer.exe
moon run app -- sfx-test --json installer.exe
moon run app -- sfx-extract --contents-only installer.exe . imported-resources
moon run app -- sfx-test --scan-bytes 2097152 --json large-stub.exe
moon run app -- --password-env ARCHIVE_PASSWORD sfx-test --json encrypted.exe
```

The default discovery bound is 1 MiB. `search_bytes=N` considers candidate
starting offsets `0..<N`; a complete 32-byte header may cross that boundary.
The whole input, including prefix and suffix, is still subject to the default
64 MiB input budget. Offsets in these APIs are Int32; this is not a seekable
large-file interface. Invalid ranges and policy violations are diagnosed.

Discovery skips signatures with an invalid start-header CRC. It selects the
first CRC-valid complete start header and immediately returns any unsupported
version, corrupt metadata, truncated extent or password error. It never hides
that failure by choosing a later archive. `open_at` lets an informed caller
select a different known offset. Multiple archives are not merged: later bytes
are retained in `suffix`. UInt64 extent overflow is checked before narrowing.

`inventory_json()` uses `moon7z.embedded_inventory.v1`, with Base64 prefix and
suffix, payload byte length/offset and the ordinary archive inventory.
`contents_verified` and `envelope_verified` remain false. The SFX test command
emits `moon7z.embedded_verification.v1` with a nested ordinary verification
report; its successful CRC checks apply only to the embedded archive.
Diagnostics inside that archive use payload-relative positions.

Contents-only export retains the existing no-replace/staging/unsafe-path rules.
It explicitly does not restore the executable, installer config, trailing data,
timestamps or attributes. Library callers retain the complete envelope bytes;
the input file stays unchanged. CRC does not establish authenticity.

## Reproducible evidence

`corpus/sfx/` contains three complete envelopes, transported as wrapped Base64
text so portable tests do not need Windows or 7-Zip. The bytes are the official
SDK 26.05 GUI `7zS2.sfx`, console `7zS2con.sfx`, and installer `7zSD.sfx` plus an
optional UTF-8 configuration, followed by an independently packed LZMA2 archive.
All three were tested with official **7za 26.05 `t` and `x`** and all three
extracted members were compared byte for byte with their originals. The SFX
executables themselves were never launched; installer execution is not tested.

| Fixture | 7z offset | Payload bytes | Decoded envelope bytes |
| --- | ---: | ---: | ---: |
| gui.base64 | 35328 | 5550 | 40878 |
| console.base64 | 34816 | 5550 | 40366 |
| installer.base64 | 129082 | 5550 | 134632 |

The members are the attributed `lzma-mbt` README/LICENSE and the project JSON
manifest, totaling 14,229 bytes. See [sources](../SOURCES.md) and
[fixture manifest](../corpus/sfx/manifest.md) for exact source/hash/license data.
The SDK is a development fixture source, never a runtime dependency.

```console
moon run checks/sfx.mbtx -- wasm
moon run checks/sfx.mbtx -- native
moon run corpus/sfx/generate.mbtx -- /path/to/7za /path/to/lzma2605 /new/output
```

The first two commands need only this checkout and the MoonBit toolchain. They
decode every fixture into a temporary directory, append a binary footer, check
JSON preservation, verify, export and compare all original bytes, then check
refusal cleanup and unchanged inputs. CI runs these commands on Wasm and native;
portable unit tests also run on Wasm-GC and JavaScript.

Synthetic regressions cover boundary-straddling headers, the default search
limit, bad-CRC decoys, credible corrupt/unsupported headers before healthy
archives, UInt64 overflow, truncated inputs, empty archives at the final eligible
offset, encrypted-header password recovery and ordinary API behavior.

Numeric split archives have a separate [volume API](volumes.md); split SFX is
not implemented. [Seekable ordinary files/volumes](seekable.md) now have a separate
API; seekable SFX discovery and Mooncakes publication remain unfinished.
