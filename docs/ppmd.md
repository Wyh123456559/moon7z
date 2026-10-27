# Import PPMd7-compressed packages

PPMd7 (`03 04 01`) is PPMdH with the 7z range coder. Moon7z decodes it directly
on Wasm, Wasm-GC, JavaScript and native, using the existing archive/member APIs.
There is no external executable, native codec binding or raw-codec public API.
This is an adaptation of the Public Domain SDK, not an original compression
algorithm; see [sources and licenses](../SOURCES.md).

## A runnable import workflow

```console
moon run app -- test --json corpus/ppmd/v2605-solid.7z
moon run app -- list --json corpus/ppmd/v2605-ppmd-header.7z
moon run app -- extract --contents-only corpus/ppmd/v2605-solid.7z . imported-ppmd
moon run checks/ppmd.mbtx -- wasm
moon run checks/ppmd.mbtx -- native
```

The normal package contains real `README.md`, `LICENSE` and Unicode-named JSON
from the attributed Apache-2.0 corpus: three files totaling 14,229 bytes.
Listing retains original metadata without claiming payload verification. The
test command checks every available CRC. Export creates a new directory only
after verification and follows the existing no-overwrite/path policies.
The check exports all seven fixtures and compares every byte with the original
documentation, manifest or generated binary. Its native mode runs the native
CLI and checks the resulting files, rather than only compiling it.

`Archive::open`, `reader().read`, `read_range`, `extract_all`, `verify`, `audit`,
comparison and host export need no new PPMd-specific options. The encrypted
fixture uses the public test password `moon7z-ppmd`; the CLI check passes it
through `--password-env`, using the same password/error contracts as other
[encrypted inputs](encrypted.md).

## Correctness and resource boundaries

Five property bytes encode order (2–64) and little-endian model memory
(2,048–4,294,967,259 bytes). Invalid values/extra property bytes are refused.
`Limits.dictionary_bytes` checks the declared model memory before arena
allocation. The implementation uses byte storage and checked Int32 offsets;
normal library size limits still cap allocations to the supported bounded range.
Alignment can add up to three bytes. Small model tables and output buffers are
additional allocations; this is not a peak-RSS claim.

The scalar range decoder requires a zero first byte, rejects an impossible
initial code, propagates input exhaustion and checks nonzero ranges/thresholds.
The model implements binary and masked escapes, frequency rescaling, context
creation, free-list splitting/coalescing and restart when model space is
exhausted. Arena accesses and bounded context walks fail with typed errors.
The existing coder-output, final-output and header quotas apply in their own
scopes; header output is not incorrectly charged to the file-byte quota.

Decoding produces the declared output length, requires final range code zero,
and refuses unconsumed packed bytes. 7z packed/folder/member CRCs are still
checked by the existing workflow. A range-coded stream uses an external output
length; some altered lengths can describe another valid stream. Matching range
termination alone does not prove the intended contents, and missing CRCs remain
explicit. CRCs do not provide authenticity.

Tests cover byte-exact solid/separate imports, encoded headers, AES composition,
range reads, deterministic comparison, dictionary/output boundaries, minimum
and unaligned arenas, order 64 initialization, truncation, trailing bytes,
unfinished range states, early exhaustion, invalid properties, 512 deterministic
malformed byte families and recovery after errors. A failed reader retains no
decoded cache. A 210,123-byte binary fixture explicitly exercises free-list
coalescing and multiple model restarts; private test counters assert both paths.

## Independent producer evidence

Official 7-Zip Extra 19.00 and 26.05 produced the compressed streams. All seven
checked-in containers pass independent `7za t` and `7za x`, followed by exact
comparison of extracted originals. The CLI encoder accepts only orders 2–32
and memory at least 64 KiB (in multiples of four); do not confuse those producer
constraints with the decoder format limits. Orders 33–64/minimum or unaligned
memory have initialization/empty-stream boundary tests here, not independent
nonempty producer fixtures.

The encoded-header fixture is a project-assembled container: its data stream is
from the 19.00 case, and its original file-table header was compressed by 26.05
PPMd. Framing/CRC fields were rebuilt by the generator. It too was independently
tested and extracted. No external archive or test suite was copied.

| Fixture | Structure | SHA-256 |
| --- | --- | --- |
| `v1900-order2.7z` | Order 2, 64 KiB model, plain header, solid | `84c80e1a2a05aed7e3a20bf7d3028884ddb744d9232de7f40483d9b1617b7120` |
| `v2605-solid.7z` | Order 6, 64 KiB model, LZMA encoded header, solid | `7f066bba6a86d9d1d674eb5b90ac26d6d1b3676f26422d9f83109f5e672152ab` |
| `v2605-order32.7z` | Order 32, solid | `3e246ac9ce533f31093ff96335d301df464a96fe54098dcee6bc330576b93a08` |
| `v2605-separate.7z` | Three PPMd folders | `43af25edeafc8400d38d3f9e354c082185ff02a7ac659c890753bc058638952c` |
| `v2605-restart.7z` | Order 16, 64 KiB model, binary restart stress | `2c100f4159be8d7e9a268163e75224fc35e8df9646b1210a91150c709ae6b454` |
| `v2605-encrypted.7z` | AES encrypted header and PPMd data | `3056716c7246bb28a6f17ecb711cc9c22f8013f02fbc89326b5d160455ff700b` |
| `v2605-ppmd-header.7z` | PPMd encoded header and PPMd data | `defa6113a1fe29854e9ca94fb3a03c247ba7b889eee95a8e68eb8529e6a685fd` |

Regenerate from the module root to a **new** directory:

```console
moon run corpus/ppmd/generate.mbtx -- PATH_TO_7ZA19 PATH_TO_7ZA26 NEW_DIRECTORY
```

The builder verifies producer banners, packing, independent testing/extraction
and byte equality. The package originals retain their existing provenance;
binary stress data and the container builder are project-authored Apache-2.0.
Regenerated encrypted bytes change because encryption uses random salt/IV.
The packer binaries are not redistributed or used at library runtime.

PPMd7 closes one codec gap. Remaining seekable input and
publication work is tracked in [the compatibility contract](compatibility.md).
