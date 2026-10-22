///|
async test "selected exports create parents and return only selected metadata in request order" {
  let root = @fs.tmpdir(prefix="moon7z-selected-test")
  defer @fs.rmdir(root, recursive=true)
  let archive = @host.open_file("corpus/lzma2-solid.7z")
  let entries = archive.entries()
  let readme = entries.filter(e => e.name == "lzma-mbt/README.md")[0]
  let manifest = entries.filter(e => e.name == "清单.json")[0]
  let selected = @host.export_selected(
    archive,
    [manifest.id, readme.id],
    parent=root,
    name="selected",
  )
  assert_eq(selected.entries, [manifest, readme])
  assert_eq(
    @fs.read_file(selected.directory + "/清单.json").binary(),
    @fs.read_file("corpus/source/清单.json").binary(),
  )
  assert_eq(
    @fs.read_file(selected.directory + "/lzma-mbt/README.md").binary(),
    @fs.read_file("corpus/source/lzma-mbt/README.md").binary(),
  )
  assert_eq(@fs.readdir(selected.directory, include_hidden=true).length(), 2)
  assert_eq(
    @fs.readdir(selected.directory + "/lzma-mbt", include_hidden=true),
    ["README.md"],
  )
}

///|
async test "directory selections are exact and empty selections are deliberate" {
  let root = @fs.tmpdir(prefix="moon7z-directory-subset")
  defer @fs.rmdir(root, recursive=true)
  let archive = @host.open_file("corpus/copy-plain.7z")
  let directory = archive.entries().filter(e => e.name == "lzma-mbt")[0]
  let selected = @host.export_selected(
    archive,
    [directory.id],
    parent=root,
    name="directory",
  )
  assert_eq(selected.entries, [directory])
  assert_eq(
    @fs.readdir(selected.directory + "/lzma-mbt", include_hidden=true),
    [],
  )
  let empty = @host.export_selected(archive, [], parent=root, name="empty")
  assert_eq(empty.entries, [])
  assert_eq(@fs.readdir(empty.directory, include_hidden=true), [])
  for
    (name, ids) in [
      ("empty", [6]),
      ("../outside", [6]),
      ("duplicate", [6, 6]),
      ("missing", [-1]),
    ] {
    let rejected = try {
      ignore(@host.export_selected(archive, ids, parent=root, name~))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_eq(@fs.readdir(empty.directory, include_hidden=true), [])
  assert_eq(@fs.readdir(root, include_hidden=true).length(), 2)
}

///|
async test "damaged solid siblings prevent selected publication and later imports recover" {
  let root = @fs.tmpdir(prefix="moon7z-bad-subset")
  defer @fs.rmdir(root, recursive=true)
  let bytes = @fs.read_file("corpus/delta-solid.7z").binary().to_array()
  bytes[40] = (bytes[40].to_int() ^ 0x40).to_byte()
  let damaged = @archive.Archive::open(Bytes::from_array(bytes))
  let rejected = try {
    ignore(@host.export_selected(damaged, [1], parent=root, name="bad"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(@fs.readdir(root, include_hidden=true), [])
  let healthy = @host.open_file("corpus/delta-solid.7z")
  let selected = @host.export_selected(
    healthy,
    [1],
    parent=root,
    name="recovered",
  )
  assert_eq(
    @fs.read_file(selected.directory + "/right.wav").binary(),
    @fs.read_file("corpus/audio/right.wav").binary(),
  )
  assert_eq(@fs.readdir(selected.directory, include_hidden=true), ["right.wav"])
}
