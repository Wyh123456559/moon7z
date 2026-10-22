///|
test "repacking equal content into other codecs or solid layouts is not a change" {
  let original = @archive.Archive::open(copy_archive)
  for input in [copy_archive, lzma_archive, lzma2_archive, separate_archive] {
    let report = original.compare(@archive.Archive::open(input))
    assert_true(report.identical())
    assert_eq(report.changes(), [])
    assert_eq(@json.parse(report.to_json().stringify()), report.to_json())
  }
}

///|
test "disjoint names produce stable added and removed changes with original IDs" {
  let left = @archive.Archive::open(binary_archive)
  let right = @archive.Archive::open(arm64_archive)
  let report = left.compare(right)
  assert_true(!report.identical())
  let changes = report.changes()
  assert_eq(changes.map(change => change.name), ["payload.bin", "program.elf"])
  assert_true(changes[0].kind == Removed)
  assert_true(changes[1].kind == Added)
  assert_eq(changes[0].left, Some(left.entries()[0]))
  assert_eq(changes[0].right, None)
  changes.clear()
  assert_eq(report.changes().length(), 2)
  assert_eq(
    report.to_json().stringify(),
    left.compare(right).to_json().stringify(),
  )
}

///|
test "corrupt content on either side prevents all comparison output even without common names" {
  let changed = binary_archive.to_array()
  changed[32] = b'\xff'
  let bad = @archive.Archive::open(Bytes::from_array(changed))
  let good = @archive.Archive::open(arm64_archive)
  assert_true(capture(() => bad.compare(good)) is Err(@archive.Checksum(..)))
  assert_true(capture(() => good.compare(bad)) is Err(@archive.Checksum(..)))
  assert_true(good.compare(good).identical())
}
