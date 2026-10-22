///|
test "7-Zip Delta and LZMA2 solid audio retains history across members" {
  let archive = @archive.Archive::open(delta_archive)
  let members = archive.extract_all()
  assert_eq(members.length(), 2)
  assert_eq(members[0].entry.name, "left.wav")
  assert_eq(members[0].bytes, audio_left)
  assert_eq(members[1].entry.name, "right.wav")
  assert_eq(members[1].bytes, audio_right)
  let report = archive.verify()
  assert_eq(report.files, 2)
  assert_eq(report.blocks, 1)
  assert_eq(report.bytes, audio_left.length() + audio_right.length())
  assert_eq(report.member_crcs_checked, 2)
  let reader = archive.reader()
  let selected = reader.read_many([1, 0, 1])
  assert_eq(selected[0], members[1])
  assert_eq(selected[1], members[0])
  assert_eq(selected[2], members[1])
  assert_eq(reader.stats().decode_attempts, 1)
  assert_eq(reader.read(0), members[0])
  assert_eq(reader.stats().cache_hits, 1)
  assert_eq(archive.extract_all(), members)
}

///|
test "7-Zip Copy and maximum-distance Delta preserve all byte values" {
  let archive = @archive.Archive::open(delta256_archive)
  let expected = Bytes::makei(256, i => i.to_byte())
  assert_eq(archive.extract_all()[0].bytes, expected)
  assert_eq(archive.reader(cache_bytes=0).read(0).bytes, expected)
  assert_eq(archive.verify().bytes, 256)
}

///|
test "filtered archives reject every truncated prefix and enforce output limits" {
  for bytes in [delta_archive, delta256_archive] {
    for length in 0..<bytes.length() {
      assert_true(
        capture(() => @archive.Archive::open(bytes[:length].to_owned()))
        is Err(_),
      )
    }
    let size = @archive.Archive::open(bytes).verify().bytes
    assert_eq(
      @archive.Archive::open(
        bytes,
        limits=@archive.Limits::new(output_bytes=size),
      ).verify().bytes,
      size,
    )
    assert_true(
      capture(() => {
        @archive.Archive::open(
          bytes,
          limits=@archive.Limits::new(output_bytes=size - 1),
        )
      })
      is Err(@archive.Limit(..)),
    )
  }
}

///|
test "failed filtered decode never poisons subsequent reads" {
  let changed = delta_archive.to_array()
  changed[40] = (changed[40].to_int() ^ 0x40).to_byte()
  let damaged = @archive.Archive::open(Bytes::from_array(changed))
  let reader = damaged.reader()
  assert_true(capture(() => reader.read(0)) is Err(_))
  assert_eq(reader.stats().cached_bytes, 0)
  assert_true(capture(() => reader.read(1)) is Err(_))
  assert_eq(reader.stats().decode_attempts, 2)
  assert_eq(
    @archive.Archive::open(delta_archive).reader().read(1).bytes,
    audio_right,
  )
}
