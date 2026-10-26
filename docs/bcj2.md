# BCJ2 graphs and executable-resource imports

An application importing x86 program/resource bundles can use the existing
`Archive::open`, `reader().read`, `verify`, `audit` and staged export APIs with
BCJ2 archives. No external decoder is launched by the library. Extracting an
executable returns its bytes; it does not execute that program.

```console
moon run app -- test corpus/bcj2/lzma2.7z
moon run app -- extract --contents-only corpus/bcj2/lzma2.7z out bcj2-import
moon run checks/bcj2.mbtx -- wasm
moon run checks/bcj2.mbtx -- native
```

The output's `part-a.bin` and `part-b.bin` must equal the corresponding originals
under `corpus/x86/`. Choose an existing parent and a new destination name for the
export command. Native commands run the native program, rather than only compile
it. The checked-in fixtures require no 7-Zip installation during verification.

## Mapping and correctness contract

Each supported coder has one output. Unary methods consume one input; BCJ2
(`03 03 01 1b`, empty properties) consumes main, call-address, jump-address and
range-control streams. The graph resolves global bindings and physical packed
input order independently of stored coder order. Duplicate bindings, duplicate
packed inputs, cycles, disconnected outputs and incorrect codec arity fail at
opening. Copy/filters preserve length; BCJ2 main/call/jump sizes must sum to its
declared output and address streams must contain whole four-byte words.

Decoding consumes every BCJ2 input exactly and requires a clean range state.
Every available physical input CRC is checked before decoding its folder, and
folder/member CRCs keep their existing scope. Solid output is reconstructed
before splitting members. One failed read does not populate the reader cache.
CRC absence remains visible; CRC is not authentication.

`Limits::new(coders=64, working_bytes=268435456)` supplies the defaults.
`coders` bounds nodes per folder; `working_bytes` bounds the sum of all declared
coder output lengths in that folder, including intermediate compressed branches
and the final output. `output_bytes` separately bounds total final folder bytes.
Consumed intermediate outputs are released. Input copies, codec dictionaries,
decoder internals and caller-owned members can coexist: this is not a peak-RSS
guarantee. Exceeding either policy returns a typed `Limit` before decoding.

## Independent corpus

The originals are this repository's Apache-2.0 instruction data and freestanding
ELF under `corpus/x86/`; no external program or peer test suite was copied.
Official 7-Zip Extra independently packed, tested and extracted all five cases;
its extracted bytes were compared with those originals before checking them in.

| Case | Producer | Structure | SHA-256 of checked-in archive |
| --- | --- | --- | --- |
| direct | 26.05 | Four raw inputs; two solid members; plain header | `e08f24af0f8d2ea32a0d44f7e0c858873bb3bab6cd15de073179a5cac6177ba1` |
| lzma2 | 26.05 | Three LZMA2 branches; two solid members; encoded header | `f299b8f5b1504c4a8330e16c1078f6c991fae33c79799746d731eaa6d728dc2c` |
| lzma19 | 19.00 | Three LZMA branches; two solid members; encoded header | `9826274e65f7224bcbfec176f14591c1bef462170b3f560f487c779ff4a58a4e` |
| separate | 26.05 | Three LZMA2 branches in each of two folders | `e093f104e944cf7718aaa86f717007ecb9fd14e41541915e22ff621a2bb642b2` |
| program | 26.05 | LZMA2 branches; one ELF member | `f11098dc73dd78c4306f336499f40fda36c703da66c73100a25d1c03893f7fc7` |

Regenerate with official 19.00 and 26.05 `7za` executables into a new directory:

```console
moon run corpus/bcj2/generate.mbtx -- PATH_TO_7ZA19 PATH_TO_7ZA26 NEW_DIRECTORY
```

The generator records actual commands in its source, switches timestamps off,
enables solid/plain or encoded headers as above and fails on any independent
test/extraction mismatch. Compressed cases explicitly bind BCJ2 input branches
with `-mb0:1 -mb0s1:2 -mb0s2:3`. Packed bytes may vary with host attributes;
member equality is the regeneration invariant. The testing executables are not
distributed or linked into Moon7z. BCJ2 algorithm adaptation/provenance is in
[SOURCES.md](../SOURCES.md); remaining compatibility gaps stay listed in the
[completion contract](compatibility.md).
