///|
test "folderwise verification agrees with full extraction for every corpus layout" {
  for
    input in [
      copy_archive, lzma_archive, lzma2_archive, separate_archive, binary_archive,
      delta_archive, delta256_archive, bcj_lzma_archive, bcj_lzma2_archive, bcj_solid_archive,
    ] {
    let archive = @archive.Archive::open(input)
    let files = archive.extract_all().filter(item => item.entry.kind == File)
    let mut total = 0
    let mut checksummed = 0
    let blocks : Set[Int32] = Set([])
    for item in files {
      total += item.bytes.length()
      if item.entry.crc32 is Some(_) {
        checksummed += 1
      }
      if item.entry.block is Some(id) {
        blocks.add(id)
      }
    }
    let report = archive.verify()
    assert_eq(report.files, files.length())
    assert_eq(report.bytes, total)
    assert_eq(report.member_crcs_checked, checksummed)
    assert_eq(report.members_without_crc, files.length() - checksummed)
    assert_eq(report.blocks, blocks.length())
    assert_eq(report, archive.verify())
    assert_eq(
      archive.reader(cache_bytes=0).read_many(files.map(item => item.entry.id)),
      files,
    )
  }
}

///|
test "verification reaches a corrupt last folder and recovers on intact input" {
  let changed = copy_archive.to_array()
  changed[32 + 14550 - 1] = (changed[32 + 14550 - 1].to_int() ^ 1).to_byte()
  let damaged = @archive.Archive::open(Bytes::from_array(changed))
  let first = damaged.entries().filter(entry => entry.block == Some(0))[0].id
  assert_true(damaged.reader().read(first).bytes.length() > 0)
  assert_true(capture(() => damaged.verify()) is Err(@archive.Checksum(..)))
  assert_true(
    capture(() => damaged.extract_all()) is Err(@archive.Checksum(..)),
  )
  assert_eq(@archive.Archive::open(copy_archive).verify().blocks, 4)
}
