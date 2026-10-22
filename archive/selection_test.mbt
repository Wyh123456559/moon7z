///|
test "selected export plans preserve request order and create only necessary parents" {
  let archive = @archive.Archive::open(copy_archive)
  let entries = archive.entries()
  let readme = entries.filter(e => e.name == "lzma-mbt/README.md")[0].id
  let manifest = entries.filter(e => e.name == "清单.json")[0].id
  let plan = archive.plan_selection([manifest, readme])
  assert_eq(plan.entries().map(e => e.id), [manifest, readme])
  assert_eq(plan.directories(), ["lzma-mbt"])
  let copy = plan.entries()
  copy.clear()
  assert_eq(plan.entries().length(), 2)
  let folders = plan.directories()
  folders.clear()
  assert_eq(plan.directories(), ["lzma-mbt"])
  let directory = entries.filter(e => e.name == "lzma-mbt")[0].id
  assert_eq(archive.plan_selection([directory]).entries().map(e => e.id), [
    directory,
  ])
  assert_eq(archive.plan_selection([directory]).directories(), ["lzma-mbt"])
  assert_eq(archive.plan_selection([]).entries(), [])
  assert_eq(archive.plan_selection([]).directories(), [])
}

///|
test "selection rejects missing IDs repeated IDs and oversized requests" {
  let archive = @archive.Archive::open(binary_archive)
  for ids in [[-1], [1], [0, -1]] {
    assert_true(
      capture(() => archive.plan_selection(ids))
      is Err(@archive.NoSuchEntry(..)),
    )
  }
  assert_true(
    capture(() => archive.plan_selection([0, 0]))
    is Err(@archive.UnsafePath(..)),
  )
  let limited = @archive.Archive::open(
    binary_archive,
    limits=@archive.Limits::new(entries=1),
  )
  assert_true(
    capture(() => limited.plan_selection([0, 0])) is Err(@archive.Limit(..)),
  )
  assert_eq(archive.plan_selection([0]).entries()[0].name, "payload.bin")
}
