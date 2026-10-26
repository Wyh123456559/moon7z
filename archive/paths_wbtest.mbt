///|
fn path_archive(entries : Array[(String, EntryKind)]) -> Archive {
  {
    input: b"",
    limits: Limits::new(),
    archive_properties: [],
    streams: {
      pack_offset: 0,
      pack_sizes: [],
      pack_crcs: [],
      blocks: [],
      layouts: [],
    },
    inventory: entries.mapi((id, pair) => {
      let (name, kind) = pair
      {
        id,
        name,
        kind,
        size: 0,
        crc32: None,
        block: None,
        metadata: {
          created: None,
          accessed: None,
          modified: None,
          attributes: None,
        },
      }
    }),
  }
}

///|
test "export planning catches collisions in either archive order" {
  for
    entries in [
      [("a", File), ("a", File)],
      [("A", File), ("a", File)],
      [("d/x", File), ("D/y", File)],
      [("a", File), ("a/b", File)],
      [("a/b", File), ("a", File)],
      [("a", Directory), ("a", Directory)],
    ] {
    let rejected = try {
      ignore(path_archive(entries).plan_contents())
      false
    } catch {
      UnsafePath(..) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "implied directories and later explicit directory entries agree" {
  let archive = path_archive([
    ("a/b/file", File),
    ("a", Directory),
    ("a/b", Directory),
    ("空目录", Directory),
  ])
  let plan = archive.plan_contents()
  assert_eq(plan.directories(), ["a", "a/b", "空目录"])
  assert_eq(plan.entries(), archive.entries())
  plan.directories().clear()
  plan.entries().clear()
  assert_eq(plan.directories().length(), 3)
  assert_eq(plan.entries().length(), 4)
}
