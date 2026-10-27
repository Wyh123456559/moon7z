///|
async test "missing empty nonregular and oversized parts fail before recovery on intact files" {
  let root = @fs.tmpdir(prefix="moon7z-volume-errors")
  defer @fs.rmdir(root, recursive=true)
  if !(@async.platform is Windows) {
    let literal = try {
      ignore(@host.open_volume_files([root + "/literal\\package.7z.001"]))
      ""
    } catch {
      err => err.to_string()
    }
    assert_true(literal.contains("single filenames"))
  }
  let paths = Array::makei(3, i => root + "/package.7z.00" + (i + 1).to_string())
  @fs.write_file(
    paths[0],
    @fs.read_file("corpus/volumes/fixed/package.7z.001").binary(),
  )
  let missing = try {
    ignore(@host.open_volume_files(paths[:]))
    ""
  } catch {
    err => err.to_string()
  }
  assert_true(missing.contains("package.7z.002"))
  @fs.write_file(paths[1], b"")
  let empty = try {
    ignore(@host.open_volume_files(paths[:]))
    ""
  } catch {
    err => err.to_string()
  }
  assert_true(empty.contains("empty"))
  @fs.remove(paths[1])
  @fs.mkdir(paths[1])
  let directory = try {
    ignore(@host.open_volume_files(paths[:]))
    false
  } catch {
    _ => true
  }
  assert_true(directory)
  @fs.rmdir(paths[1])
  for i in 1..<3 {
    @fs.write_file(
      paths[i],
      @fs.read_file("corpus/volumes/fixed/package.7z.00" + (i + 1).to_string()).binary(),
    )
  }
  let limited = try {
    ignore(
      @host.open_volume_files(
        paths[:],
        limits=@archive.Limits::new(input_bytes=5549),
      ),
    )
    ""
  } catch {
    err => err.to_string()
  }
  assert_true(limited.contains("combined volume input"))
  assert_eq(
    @host.open_volume_files(
      paths[:],
      limits=@archive.Limits::new(input_bytes=5550),
    ).archive.verify().bytes,
    14229,
  )
  assert_eq(@fs.readdir(root).length(), 3)
}
