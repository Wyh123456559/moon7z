///|
test "strict member CRC policy accepts complete archives without changing reports" {
  for
    bytes in [
      binary_archive, delta_archive, delta256_archive, bcj_lzma_archive, bcj_lzma2_archive,
      bcj_solid_archive,
    ] {
    let archive = @archive.Archive::open(bytes)
    let report = archive.verify(require_member_crcs=true)
    assert_eq(report, archive.verify())
    assert_eq(report.members_without_crc, 0)
  }
}

///|
test "strict policy identifies empty files without treating directories as files" {
  for bytes in [copy_archive, lzma_archive, lzma2_archive, separate_archive] {
    let archive = @archive.Archive::open(bytes)
    let empty = archive.entries().filter(e => e.kind == File && e.crc32 is None)
    assert_eq(empty.length(), 1)
    assert_eq(empty[0].name, "empty.txt")
    assert_eq(archive.verify().members_without_crc, 1)
    let error = capture(() => archive.verify(require_member_crcs=true))
    match error {
      Err(@archive.MissingChecksum(id~, name~)) => {
        assert_eq(id, empty[0].id)
        assert_eq(name, "empty.txt")
      }
      _ => fail("expected the missing file checksum")
    }
    assert_eq(archive.verify(), archive.verify(require_member_crcs=false))
  }
}

///|
test "strict CRC presence never replaces actual checksum verification" {
  let damaged = binary_archive.to_array()
  damaged[32] = (damaged[32].to_int() ^ 1).to_byte()
  let archive = @archive.Archive::open(Bytes::from_array(damaged))
  assert_true(
    capture(() => archive.verify(require_member_crcs=true))
    is Err(@archive.Checksum(..)),
  )
  assert_eq(
    @archive.Archive::open(binary_archive).verify(require_member_crcs=true).files,
    1,
  )
}
