///|
test "7-Zip BCJ with LZMA and LZMA2 restores an actual x86-64 executable" {
  for bytes in [bcj_lzma_archive, bcj_lzma2_archive] {
    let archive = @archive.Archive::open(bytes)
    assert_eq(archive.verify().member_crcs_checked, 1)
    let members = archive.extract_all()
    assert_eq(members.length(), 1)
    assert_eq(members[0].entry.name, "program.elf")
    assert_eq(members[0].bytes, x86_program)
    assert_eq(archive.reader().read(0), members[0])
    assert_eq(archive.extract_all(), members)
  }
}

///|
test "BCJ instructions crossing solid members retain full-folder state" {
  let archive = @archive.Archive::open(bcj_solid_archive)
  let members = archive.extract_all()
  assert_eq(members[0].bytes, x86_first)
  assert_eq(members[1].bytes, x86_second)
  let reader = archive.reader()
  let selected = reader.read_many([1, 0, 1])
  assert_eq(selected[0], members[1])
  assert_eq(selected[1], members[0])
  assert_eq(selected[2], members[1])
  assert_eq(reader.stats().decode_attempts, 1)
  assert_eq(archive.verify().member_crcs_checked, 2)
}

///|
test "BCJ truncation corruption limits and recovery" {
  for bytes in [bcj_lzma_archive, bcj_lzma2_archive, bcj_solid_archive] {
    for length in 0..<bytes.length() {
      assert_true(
        capture(() => @archive.Archive::open(bytes[:length].to_owned()))
        is Err(_),
      )
    }
    let total = @archive.Archive::open(bytes).verify().bytes
    assert_eq(
      @archive.Archive::open(
        bytes,
        limits=@archive.Limits::new(output_bytes=total),
      ).verify().bytes,
      total,
    )
    assert_true(
      capture(() => {
        @archive.Archive::open(
          bytes,
          limits=@archive.Limits::new(output_bytes=total - 1),
        )
      })
      is Err(@archive.Limit(..)),
    )
  }
  let changed = bcj_solid_archive.to_array()
  changed[32] = b'\x90'
  let reader = @archive.Archive::open(Bytes::from_array(changed)).reader()
  assert_true(capture(() => reader.read(1)) is Err(@archive.Checksum(..)))
  assert_eq(reader.stats().cached_bytes, 0)
  assert_eq(
    @archive.Archive::open(bcj_solid_archive).reader().read(1).bytes,
    x86_second,
  )
}
