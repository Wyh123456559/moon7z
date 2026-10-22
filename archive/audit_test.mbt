///|
test "audit accounts for every folder and retains unstreamed and unchecked metadata" {
  for bytes in [copy_archive, lzma2_archive, delta_archive, arm64_wrap_archive] {
    let archive = @archive.Archive::open(bytes)
    let audit = archive.audit()
    assert_true(audit.all_available_checks_passed())
    let ids : Array[Int32] = []
    let mut decoded = 0
    for folder in audit.folders() {
      assert_true(folder.passed())
      assert_true(folder.error is None)
      decoded += folder.bytes
      for entry in folder.entries() {
        ids.push(entry.id)
      }
      let copy = folder.entries()
      copy.clear()
      assert_true(!folder.entries().is_empty())
    }
    for entry in audit.entries_without_data() {
      ids.push(entry.id)
    }
    ids.sort_by((a, b) => a - b)
    assert_eq(ids, archive.entries().map(entry => entry.id))
    assert_eq(decoded, archive.verify().bytes)
    assert_eq(
      audit.files_without_crc().length(),
      archive.verify().members_without_crc,
    )
    assert_eq(@json.parse(audit.to_json().stringify()), audit.to_json())
    let folders = audit.folders()
    folders.clear()
    assert_true(!audit.folders().is_empty())
  }
}

///|
test "audit continues past corrupt first and last folders without releasing payloads" {
  let changed = copy_archive.to_array()
  for offset in [32, 32 + 14550 - 1] {
    changed[offset] = (changed[offset].to_int() ^ 1).to_byte()
  }
  let archive = @archive.Archive::open(Bytes::from_array(changed))
  let audit = archive.audit()
  assert_true(!audit.all_available_checks_passed())
  let folders = audit.folders()
  assert_eq(folders.length(), 4)
  assert_true(folders[0].error is Some(@archive.Checksum(..)))
  assert_true(folders[1].passed())
  assert_true(folders[2].passed())
  assert_true(folders[3].error is Some(@archive.Checksum(..)))
  assert_true(
    archive.reader().read(folders[1].entries()[0].id).bytes.length() > 0,
  )
  assert_true(capture(() => archive.verify()) is Err(@archive.Checksum(..)))
  assert_eq(audit.to_json().stringify(), archive.audit().to_json().stringify())
  assert_true(
    audit.to_json()
    is {
      "all_available_checks_passed": False,
      "folders": Array(
        [{ "error": { "code": String("checksum"), .. }, .. }, _, _, _]
      ),
      ..
    },
  )
  assert_true(
    @archive.Archive::open(copy_archive).audit().all_available_checks_passed(),
  )
}
