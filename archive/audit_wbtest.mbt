///|
test "empty data audits retain missing file CRCs without inventing folder failures" {
  let archive = named_empty_archive(["a", "a"])
  let report = archive.audit()
  assert_true(report.all_available_checks_passed())
  assert_eq(report.folders().length(), 0)
  assert_eq(report.files_without_crc().map(entry => entry.id), [0, 1])
  let entries = report.entries_without_data()
  entries.clear()
  assert_eq(report.entries_without_data().length(), 2)
  let missing = report.files_without_crc()
  missing.clear()
  assert_eq(report.files_without_crc().length(), 2)
}

///|
test "audit records an invalid decoded length then checks the following folder" {
  let meta : Metadata = {
    start_position: None,
    created: None,
    accessed: None,
    modified: None,
    attributes: None,
  }
  let model = comparison_archive([
    ("bad", File, b"NO", meta),
    ("good", File, b"YES", meta),
  ])
  model.streams.blocks[0].size = 3
  let report = model.audit()
  assert_true(report.folders()[0].error is Some(Invalid(..)))
  assert_true(report.folders()[1].passed())
  assert_true(!report.all_available_checks_passed())
}

///|
test "structured diagnostics retain numeric fields escaped names and recovery hints" {
  let errors : Array[ArchiveError] = [
    InvalidRange(id=4, offset=-1, length=0x7fffffff, size=2),
    AmbiguousName(name="\"目录\"\n", first_id=0, second_id=7),
    Checksum(scope="folder 2"),
    MissingChecksum(id=8, name="empty.txt"),
    Invalid(offset=3, reason="bad data"),
    Unsupported(feature="encrypted"),
    Limit(resource="output", maximum=5),
    Codec(reason="truncated"),
    UnsafePath(path="../x", reason="parent"),
    NoSuchEntry(id=-1),
  ]
  for error in errors {
    let document = error.to_json()
    assert_eq(@json.parse(document.stringify()), document)
    assert_true(
      document is { "message": String(message), .. } && !message.is_empty(),
    )
  }
  assert_true(
    errors[0].to_json()
    is {
      "code": String("invalid_range"),
      "offset": Number(-1, ..),
      "length": Number(2147483647, ..),
      ..
    },
  )
  assert_true(
    errors[1].to_json()
    is {
      "code": String("ambiguous_name"),
      "name": String("\"目录\"\n"),
      "first_id": Number(0, ..),
      "second_id": Number(7, ..),
      ..
    },
  )
}
