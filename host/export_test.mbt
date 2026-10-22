///|
async test "verified exports reproduce all files and preserve existing targets" {
  let root = @fs.tmpdir(prefix="moon7z-export-test")
  defer @fs.rmdir(root, recursive=true)
  let archive = @host.open_file("corpus/lzma2-solid.7z")
  let expected = archive.extract_all()
  let output = @host.export_contents(archive, parent=root, name="imported")
  assert_eq(output.entries, archive.entries())
  for item in expected {
    let path = output.directory + "/" + item.entry.name
    if item.entry.kind == File {
      assert_eq(@fs.read_file(path).binary(), item.bytes)
    } else {
      assert_true(@fs.kind(path, follow_symlink=false) == Directory)
    }
  }
  @fs.write_file(output.directory + "/keep.txt", "unrelated")
  let rejected = try {
    ignore(@host.export_contents(archive, parent=root, name="imported"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(@fs.read_file(output.directory + "/keep.txt").text(), "unrelated")
  assert_eq(@fs.readdir(root, include_hidden=true), ["imported"])
}

///|
async test "empty directories and regular files are never replaced" {
  let root = @fs.tmpdir(prefix="moon7z-existing-test")
  defer @fs.rmdir(root, recursive=true)
  let archive = @host.open_file("corpus/copy-plain.7z")
  @fs.mkdir(root + "/empty")
  @fs.write_file(root + "/file", "keep")
  for name in ["empty", "file"] {
    let rejected = try {
      ignore(@host.export_contents(archive, parent=root, name~))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_eq(@fs.readdir(root + "/empty"), [])
  assert_eq(@fs.read_file(root + "/file").text(), "keep")
  let remaining = @fs.readdir(root, include_hidden=true)
  assert_eq(remaining.length(), 2)
  assert_true(remaining.contains("empty") && remaining.contains("file"))
}

///|
async test "invalid names and damaged input publish no output" {
  let root = @fs.tmpdir(prefix="moon7z-rejected-test")
  defer @fs.rmdir(root, recursive=true)
  let archive = @host.open_file("corpus/copy-plain.7z")
  for name in ["../outside", "a/b", "NUL"] {
    let rejected = try {
      ignore(@host.export_contents(archive, parent=root, name~))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let bytes = @fs.read_file("corpus/copy-plain.7z").binary().to_array()
  bytes[32] = (bytes[32].to_int() ^ 1).to_byte()
  let broken = @archive.Archive::open(Bytes::from_array(bytes))
  let rejected = try {
    ignore(@host.export_contents(broken, parent=root, name="damaged"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(@fs.readdir(root, include_hidden=true), [])
  ignore(@host.export_contents(archive, parent=root, name="recovered"))
  assert_eq(@fs.readdir(root, include_hidden=true), ["recovered"])
}

///|
async test "bounded file reader rejects directories and oversized files" {
  let rejected = try {
    ignore(
      @host.open_file(
        "corpus/copy-plain.7z",
        limits=@archive.Limits::new(input_bytes=1),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let rejected = try {
    ignore(@host.open_file("corpus"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
