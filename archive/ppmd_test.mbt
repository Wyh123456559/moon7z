///|
test "independent PPMd7 archives preserve text bytes across order solid layout and encryption" {
  for
    (bytes, blocks, encrypted) in [
      (ppmd19, 1, false),
      (ppmd26, 1, false),
      (ppmd32, 1, false),
      (ppmd_separate, 3, false),
      (ppmd_header, 1, false),
      (ppmd_encrypted, 1, true),
    ] {
    let archive = @archive.Archive::open(bytes, password="moon7z-ppmd")
    assert_eq(archive.is_encrypted(), encrypted)
    let expected : Map[String, Bytes] = {
      "README.md": upstream_readme,
      "LICENSE": upstream_license,
      "清单.json": manifest,
    }
    for item in archive.extract_all() {
      assert_eq(item.bytes, expected[item.entry.name])
    }
    let reader = archive.reader()
    let entries = archive.entries()
    for entry in entries {
      assert_eq(reader.read(entry.id).bytes, expected[entry.name])
      assert_eq(
        reader.read_range(entry.id, offset=0, length=1),
        expected[entry.name][:1].to_owned(),
      )
    }
    assert_eq(archive.verify().bytes, 14229)
    assert_eq(archive.verify().blocks, blocks)
    assert_true(archive.audit().all_available_checks_passed())
    assert_true(archive.compare(@archive.Archive::open(ppmd26)).identical())
  }
  assert_true(
    capture(() => @archive.Archive::open(ppmd_encrypted))
    is Err(@archive.PasswordRequired),
  )
  assert_true(
    capture(() => @archive.Archive::open(ppmd_encrypted, password="wrong"))
    is Err(@archive.DecryptionFailed),
  )
  let limit = capture(() => {
    @archive.Archive::open(
      ppmd26,
      limits=@archive.Limits::new(dictionary_bytes=65535),
    )
  })
  assert_true(limit is Err(@archive.Limit(..)))
  let original = Bytes::makei(210123, i => ((i * 73 + i / 257) & 255).to_byte())
  assert_eq(
    @archive.Archive::open(ppmd_restart).extract_all()[0].bytes,
    original,
  )
  let damaged = ppmd19.to_array()
  damaged[32] = b'\x01'
  let broken = @archive.Archive::open(Bytes::from_array(damaged))
  let reader = broken.reader()
  assert_true(capture(() => reader.read(0)) is Err(@archive.Codec(..)))
  assert_eq(reader.stats().cached_bytes, 0)
  assert_true(capture(() => reader.read(0)) is Err(@archive.Codec(..)))
  assert_true(!broken.audit().all_available_checks_passed())
  assert_eq(@archive.Archive::open(ppmd19).verify().bytes, 14229)
}
