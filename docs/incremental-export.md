# Incremental staged contents export

Use the existing `@host.export_contents` or `@host.export_selected` APIs to
publish a new contents-only directory. Their signatures, selected-entry order
and metadata contracts are unchanged. No extra option is required.

```console
moon run app -- extract --contents-only corpus/copy-plain.7z . imported-tree
moon run checks/incremental-export.mbtx -- wasm
moon run checks/incremental-export.mbtx -- native
```

Choose a new destination name for the first command. The checks create their own
temporary directories, corrupt the last packed folder in the checked-in real
archive, and exercise both complete and selected exports. Both must fail with
empty stdout and leave no destination or staging directory. The checks then
export an unaffected subset and an intact full archive and compare real bytes.

All selected IDs, archive paths, path collisions and the destination name are
planned before staging. Writes are grouped by selected data folder. The reader
checks all available packed, folder and sibling-member CRCs before the first
file from a folder is written. It caches that folder while its selected files
are copied and written individually. The cache budget includes unselected solid
siblings, so even a small selection does not repeatedly decode the same folder.
Unselected folders are still outside a selected export's verification scope.

The write schedule contains metadata only. It does not accumulate the owned
contents of earlier files. The reader retains at most one decoded folder and
releases the previous one before loading another; the current member's owned
buffer is local to its write. Empty files need no data folder. Returned entries
retain archive order for complete exports and request order for selected exports,
independently of write scheduling. Directories and original metadata are retained
as before; timestamps and attributes are not applied to disk.

A later folder can fail after earlier checked files have been written to the
private staging directory. Cleanup removes those files on failure. Publication
still uses a no-replace rename only after every selected folder and write has
succeeded. Existing destinations, including empty directories, are refused.
Callers must control the existing parent throughout export; hostile concurrent
filesystem mutation and failure to remove staging are governed by the existing
export contract. A cleanup failure is returned as an I/O error.

This is incremental output, not a streaming 7z input reader: archive input,
packed data, decoder buffers, one full solid folder and the current member copy
may coexist. Archive resource limits remain in force. No RSS ceiling, benchmark
or speed advantage is claimed. `extract_all()` deliberately retains its original
API returning all owned contents and is not changed by this disk export path.
