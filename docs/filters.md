# Classic 7z branch and byte-swap filters

The reader accepts these registered 7z methods as length-preserving nodes in a
bounded coder graph, including the Copy/LZMA/LZMA2 pipelines demonstrated here:

| Name | Method ID | Properties / initial position |
| --- | --- | --- |
| ARM | `03 03 05 01` | empty / zero |
| ARM-Thumb | `03 03 07 01` | empty / zero |
| PowerPC | `03 03 02 05` | empty / zero |
| IA64 | `03 03 04 01` | empty / zero |
| SPARC | `03 03 08 05` | empty / zero |
| Swap2 | `02 03 02` | empty |
| Swap4 | `02 03 04` | empty |

The branch algorithms are reused from `aurora0x27/lzma-mbt@0.1.0/filters`;
the 7z IDs, container bindings, validation and workflow integration are Moon7z
code. Generic XZ filter IDs are not silently treated as aliases for classic
7z methods. Nonempty classic branch properties are explicitly unsupported.
In particular, an ARM64 initial-offset property must not be applied to ARM,
PowerPC, IA64 or SPARC just because their dependency APIs also accept an offset.

Each transform runs on the complete decoded folder before member slicing. The
checked corpus splits the first instruction after three bytes; resetting the
filter at the second member would produce incorrect content. A partial final
instruction or swap group remains present unchanged. Original member metadata,
CRC validation, selection scope and output budgets retain their existing rules.

## Independent evidence

`corpus/branches/` contains seven Copy/plain-header archives and five
LZMA2/compressed-header archives. The 65,539-byte original combines explicitly
chosen branch words/bundles with deterministic byte patterns and an odd tail.
The first member is three bytes; the second holds the rest. All twelve were
packed, tested and extracted by 7zr 26.04 and their output compared byte-for-byte
with the originals. These are generated test bytes, not programs executed on the
named architectures. The tests check that the plain filtered payload actually
differs from the original; an inactive transform cannot satisfy this evidence.

Portable tests cover both codecs, complete member bytes, range/batch reads,
comparison across repacking, strict member CRCs, damaged data, limits, truncated
inputs and successful reads after a failure. Unit tests also cover sizes zero
through 65, property refusal, swap involutions/composition and incomplete tails.
No claim is made about every possible instruction sequence or peak memory.

```console
moon run checks/branches.mbtx -- wasm
moon run checks/branches.mbtx -- native
```

To regenerate into a **new, nonexistent directory**, pass an installed 7zr/7z
executable and a new output path. Existing archives are never updated in place:

```console
moon run corpus/branches/generate.mbtx -- /path/to/7zr /tmp/new-branch-corpus
moon run checks/branches.mbtx -- wasm /tmp/new-branch-corpus
```

The generator performs the independent pack/test/extract cycle itself. Runtime
library consumers and normal CI tests do not need a packer. Source, dependency
and packer licensing are recorded in [SOURCES.md](../SOURCES.md).
