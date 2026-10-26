///|
test "BCJ2 real four-stream graphs preserve solid members and separate folders" {
  for
    (bytes, blocks) in [
      (bcj2_direct, 1),
      (bcj2_lzma2, 1),
      (bcj2_lzma19, 1),
      (bcj2_separate, 2),
    ] {
    let archive = @archive.Archive::open(bytes)
    let reader = archive.reader()
    let entries = archive.entries()
    assert_eq(entries.length(), 2)
    for entry in entries {
      let expected = if entry.name == "part-a.bin" {
        x86_first
      } else {
        x86_second
      }
      assert_eq(reader.read(entry.id).bytes, expected)
    }
    assert_eq(archive.verify().blocks, blocks)
    assert_eq(archive.verify().bytes, x86_first.length() + x86_second.length())
    assert_eq(archive.extract_all(), archive.extract_all())
    assert_true(archive.audit().all_available_checks_passed())
    assert_true(
      archive.compare(@archive.Archive::open(bcj2_direct)).identical(),
    )
  }
  let program = @archive.Archive::open(bcj2_program)
  assert_eq(program.extract_all()[0].bytes, x86_program)
}

///|
test "BCJ2 graph resource limits refuse before exposing content" {
  assert_true(
    capture(() => {
      @archive.Archive::open(bcj2_lzma2, limits=@archive.Limits::new(coders=3))
    })
    is Err(@archive.Limit(..)),
  )
  assert_true(
    capture(() => {
      @archive.Archive::open(
        bcj2_lzma2,
        limits=@archive.Limits::new(working_bytes=4099),
      )
    })
    is Err(@archive.Limit(..)),
  )
  assert_true(
    capture(() => {
      @archive.Archive::open(
        bcj2_direct,
        limits=@archive.Limits::new(output_bytes=4098),
      )
    })
    is Err(@archive.Limit(..)),
  )
  assert_eq(@archive.Archive::open(bcj2_lzma2).verify().bytes, 4099)
}
