///|
test "BZip2 real solid and separate imports preserve audio and structured metadata" {
  for (bytes, blocks) in [(bzip_1900, 2), (bzip_2605, 2), (bzip_separate, 3)] {
    let archive = @archive.Archive::open(bytes)
    let reader = archive.reader()
    for entry in archive.entries() {
      let expected = match entry.name {
        "left.wav" => audio_left
        "right.wav" => audio_right
        _ => manifest
      }
      assert_eq(reader.read(entry.id).bytes, expected)
    }
    assert_eq(archive.verify().bytes, 32908)
    assert_eq(archive.verify().blocks, blocks)
    assert_true(archive.audit().all_available_checks_passed())
    assert_true(archive.compare(@archive.Archive::open(bzip_1900)).identical())
  }
  assert_eq(
    @archive.Archive::open(bzip_runs).extract_all()[0].bytes,
    b"a".repeat(1100000),
  )
  assert_eq(
    @archive.Archive::open(bzip_blocks).extract_all()[0].bytes,
    Bytes::makei(210123, i => ((i * 73 + i / 257) & 255).to_byte()),
  )
  let limited = @archive.Archive::open(
    bzip_runs,
    limits=@archive.Limits::new(dictionary_bytes=99999),
  )
  assert_true(capture(() => limited.verify()) is Err(@archive.Limit(..)))
  assert_eq(@archive.Archive::open(bzip_runs).verify().bytes, 1100000)
}
