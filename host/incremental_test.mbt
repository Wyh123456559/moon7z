///|
async test "a late damaged folder rolls back staged earlier files and later exports recover" {
  let root = @fs.tmpdir(prefix="moon7z-late-export")
  defer @fs.rmdir(root, recursive=true)
  let bytes = @fs.read_file("corpus/copy-plain.7z").binary().to_array()
  bytes[32 + 14550 - 1] = (bytes[32 + 14550 - 1].to_int() ^ 1).to_byte()
  let damaged = @archive.Archive::open(Bytes::from_array(bytes))
  let files = damaged
    .entries()
    .filter(entry => entry.kind == File && entry.block is Some(_))
  let first = files[0]
  let last = files[files.length() - 1]
  assert_true(first.block != last.block)
  for subset in [false, true] {
    let rejected = try {
      if subset {
        ignore(
          @host.export_selected(
            damaged,
            [first.id, last.id],
            parent=root,
            name="bad",
          ),
        )
      } else {
        ignore(@host.export_contents(damaged, parent=root, name="bad"))
      }
      false
    } catch {
      @archive.Checksum(..) => true
      err => raise err
    }
    assert_true(rejected)
    assert_eq(@fs.readdir(root, include_hidden=true), [])
  }
  let healthy_part = @host.export_selected(
    damaged,
    [first.id],
    parent=root,
    name="healthy-part",
  )
  assert_eq(
    @fs.read_file(healthy_part.directory + "/" + first.name).binary(),
    @fs.read_file("corpus/source/" + first.name).binary(),
  )
  let intact = @host.open_file("corpus/copy-plain.7z")
  let restored = @host.export_contents(intact, parent=root, name="restored")
  assert_eq(restored.entries, intact.entries())
  for entry in restored.entries {
    if entry.kind == File {
      assert_eq(
        @fs.read_file(restored.directory + "/" + entry.name).binary(),
        @fs.read_file("corpus/source/" + entry.name).binary(),
      )
    }
  }
  assert_eq(@fs.readdir(root, include_hidden=true).length(), 2)
}
