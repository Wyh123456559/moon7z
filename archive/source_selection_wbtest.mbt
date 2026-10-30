///|
fn source_test_model(archive : Archive) -> SourceArchive {
  {
    source: SeekableInput::new(archive.input.length().to_uint64(), (
      offset,
      length,
    ) => archive.input[offset.to_int():offset.to_int() + length].to_owned()),
    limits: archive.limits,
    crypto: archive.crypto,
    streams: archive.streams,
    inventory: archive.inventory,
    auxiliary: archive.auxiliary,
    archive_properties: archive.archive_properties,
    file_extensions: archive.file_extensions,
  }
}

///|
test "positioned path plans preserve safe subsets and refuse aliases and opaque semantics" {
  let model = named_empty_archive([
    "../outside", "safe/report.txt", "SAFE/report.txt", "safe", "safe/report.txt",
  ])
  let source = source_test_model(model)
  assert_eq(source.plan_selection([1]).directories(), ["safe"])
  assert_eq(source.plan_selection([4]).entries()[0].id, 4)
  for ids in [[0], [1, 2], [1, 3], [1, 4], [1, 1]] {
    assert_true(
      try {
        ignore(source.plan_selection(ids[:]))
        false
      } catch {
        UnsafePath(..) => true
        _ => false
      },
    )
  }
  assert_true(
    try {
      ignore(source.plan_selection([-1]))
      false
    } catch {
      NoSuchEntry(..) => true
      _ => false
    },
  )
  source.file_extensions.push({ id: 128UL, data: b"opaque", })
  assert_true(
    try {
      ignore(source.plan_selection([1]))
      false
    } catch {
      UnsafePath(..) => true
      _ => false
    },
  )
  assert_eq(source.plan_selection([]).entries(), [])
}
