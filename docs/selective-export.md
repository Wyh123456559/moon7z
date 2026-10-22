# Export an explicit resource subset

An importer often needs a manifest and a few resources rather than an entire
package tree. Select stable entry IDs, inspect the path plan, then publish those
contents into a new directory. Names and metadata remain unchanged.

```console
moon run app -- list --json corpus/lzma2-solid.7z
moon run app -- extract-selected --contents-only corpus/lzma2-solid.7z . selected-manifest 6
moon run checks/subset.mbtx -- wasm
```

The first command identifies `清单.json` as ID 6. The second creates
`selected-manifest/清单.json` and no other archive members. It refuses an existing
`selected-manifest`, including an empty directory. The check compares the output
with the original JSON, tests duplicate/missing IDs and overwrite refusal, and
proves that an independent healthy folder can be selected from a damaged archive.
Replace the check's `wasm` argument with `native` to run the native CLI.

In library code, `Archive::plan_selection(ids)` returns the required directories
and original selected entries without decoding. `@host.export_selected` uses that
plan, reads the selected members and publishes a new tree only after all selected
data checks succeed. `ExportedContents.entries` retains request order, stable IDs
and original metadata. The exporter does not apply timestamps or attributes.

The selection is exact. A directory ID includes only that directory. Select its
descendant IDs explicitly if desired; parent directories of selected files are
created automatically. No recursion or hidden name expansion occurs. Duplicate
names stay individually addressable by ID, but selecting colliding paths for a
single export is rejected. Paths of unselected entries are outside this subset's
path plan; every selected path must pass the portable safety checks.

The library accepts an empty ID array to deliberately create an empty directory.
The CLI requires at least one ID. Negative/out-of-range IDs, repeated IDs, invalid
destination names and path aliases fail without publishing or leaving staging
output. The destination's existing parent must remain under the caller's control
throughout the operation, as required by the full exporter.

Integrity is scoped to selected folders. A selected solid folder is decoded in
full and all its available sibling CRCs are checked before any file is written.
Unselected folders are not decoded or verified. To require whole-archive checks,
call `verify()` first; to require a CRC for every file, use
`verify(require_member_crcs=true)` first. Missing CRCs are not authenticity proofs.
