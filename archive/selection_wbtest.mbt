///|
fn named_empty_archive(names : Array[String]) -> Archive {
  {
    input: b"",
    limits: Limits::new(),
    archive_properties: [],
    auxiliary: [],
    file_extensions: [],
    crypto: CryptState::new(None, Limits::new()),
    streams: {
      pack_offset: 0,
      pack_sizes: [],
      pack_crcs: [],
      blocks: [],
      layouts: [],
    },
    inventory: names.mapi((id, name) => {
      anti: false,
      id,
      name,
      kind: File,
      size: 0,
      crc32: None,
      block: None,
      metadata: {
        start_position: None,
        created: None,
        accessed: None,
        modified: None,
        attributes: None,
      },
    }),
  }
}

///|
test "unselected unsafe names are excluded but selected path conflicts are rejected" {
  let archive = named_empty_archive([
    "../outside", "safe/report.txt", "SAFE/report.txt", "safe", "safe/report.txt",
  ])
  assert_eq(archive.plan_selection([1]).directories(), ["safe"])
  for ids in [[0], [1, 2], [1, 3], [1, 4]] {
    let rejected = try {
      ignore(archive.plan_selection(ids))
      false
    } catch {
      UnsafePath(..) => true
      _ => false
    }
    assert_true(rejected)
  }
  let all_rejected = try {
    ignore(archive.plan_contents())
    false
  } catch {
    UnsafePath(..) => true
    _ => false
  }
  assert_true(all_rejected)
  assert_eq(archive.plan_selection([4]).entries()[0].id, 4)
}
