///|
test "real DEFLATE audio and manifest imports compare identically across producers and folder layouts" {
  for
    (bytes, blocks) in [
      (deflate_1900, 2),
      (deflate_2605, 2),
      (deflate_separate, 3),
      (deflate_level0, 2),
    ] {
    let archive = @archive.Archive::open(bytes)
    assert_eq(archive.entries().length(), 3)
    let reader = archive.reader()
    for entry in archive.entries() {
      let expected = match entry.name {
        "left.wav" => audio_left
        "right.wav" => audio_right
        _ => manifest
      }
      assert_eq(reader.read(entry.id).bytes, expected)
    }
    assert_eq(archive.verify().blocks, blocks)
    assert_eq(archive.verify().bytes, 32908)
    assert_true(archive.audit().all_available_checks_passed())
    assert_true(
      archive.compare(@archive.Archive::open(deflate_1900)).identical(),
    )
  }
  assert_true(
    capture(() => {
      @archive.Archive::open(
        deflate_2605,
        limits=@archive.Limits::new(dictionary_bytes=32767),
      )
    })
    is Err(@archive.Limit(..)),
  )
  assert_eq(@archive.Archive::open(deflate_2605).verify().bytes, 32908)
}
