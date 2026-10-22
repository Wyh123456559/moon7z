///|
async test "export schedules cache complete selected folders and decode each at most once" {
  for path in ["copy-plain", "lzma2-solid", "lzma2-separate"] {
    let archive = open_file("corpus/" + path + ".7z")
    let selected = archive.entries().rev()
    let (scheduled, cache_bytes) = export_schedule(archive, selected)
    let expected = selected.filter(entry => entry.kind == File)
    assert_eq(scheduled.length(), expected.length())
    let reader = archive.reader(cache_bytes~)
    let folders : Set[Int32] = Set([])
    for entry in scheduled {
      if entry.block is Some(id) {
        folders.add(id)
      }
      assert_eq(
        reader.read(entry.id).bytes,
        @fs.read_file("corpus/source/" + entry.name).binary(),
      )
    }
    assert_eq(reader.stats().decode_attempts, folders.length())
    assert_true(reader.stats().cached_bytes <= cache_bytes)
    assert_eq(
      export_schedule(archive, selected).0.map(entry => entry.id),
      scheduled.map(entry => entry.id),
    )
    reader.clear_cache()
    assert_eq(reader.stats().cached_bytes, 0)
  }
}

///|
async test "a tiny solid selection budgets all siblings while empty selections decode nothing" {
  let archive = open_file("corpus/lzma2-solid.7z")
  let entries = archive.entries()
  let manifest = entries.filter(entry => entry.name == "清单.json")[0]
  let (scheduled, cache_bytes) = export_schedule(archive, [manifest])
  assert_eq(scheduled, [manifest])
  assert_eq(cache_bytes, archive.verify().bytes)
  assert_true(cache_bytes > manifest.size)
  let empty = entries.filter(entry => entry.kind == File && entry.block is None)
  let (scheduled, cache_bytes) = export_schedule(archive, empty)
  assert_eq(scheduled, empty)
  assert_eq(cache_bytes, 0)
  assert_eq(export_schedule(archive, []).0, [])
  assert_eq(export_schedule(archive, []).1, 0)
}
