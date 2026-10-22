///|
test "7-Zip ARM64 and LZMA2 reproduce a complete AArch64 ELF" {
  let archive = @archive.Archive::open(arm64_archive)
  let members = archive.extract_all()
  assert_eq(members.length(), 1)
  assert_eq(members[0].entry.name, "program.elf")
  assert_eq(members[0].bytes, arm64_program)
  assert_eq(archive.verify(require_member_crcs=true).bytes, 144)
  assert_eq(
    archive.reader().read_range(0, offset=120, length=24),
    arm64_program[120:].to_owned(),
  )
}

///|
test "aligned ARM64 offset and UInt32 wrap retain state across solid members" {
  for bytes in [arm64_offset_archive, arm64_wrap_archive] {
    let archive = @archive.Archive::open(bytes)
    let members = archive.extract_all()
    assert_eq(members[0].entry.name, "a-head.bin")
    assert_eq(members[0].bytes, arm64_head)
    assert_eq(members[1].bytes, arm64_tail)
    let report = archive.verify(require_member_crcs=true)
    assert_eq(report.files, 2)
    assert_eq(report.blocks, 1)
    assert_eq(report.bytes, 4403)
    let reader = archive.reader()
    assert_eq(reader.read_many([1, 0, 1]), [members[1], members[0], members[1]])
    assert_eq(reader.stats().decode_attempts, 1)
    assert_eq(reader.read_range(1, offset=4397, length=3), b"\xaa\xbb\xcc")
    assert_eq(reader.stats().cache_hits, 1)
    assert_eq(archive.extract_all(), members)
  }
}

///|
test "ARM64 archives reject truncation resource excess and corruption then recover" {
  for bytes in [arm64_archive, arm64_offset_archive, arm64_wrap_archive] {
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
  let changed = arm64_offset_archive.to_array()
  changed[32] = (changed[32].to_int() ^ 1).to_byte()
  let reader = @archive.Archive::open(Bytes::from_array(changed)).reader()
  assert_true(capture(() => reader.read(1)) is Err(@archive.Checksum(..)))
  assert_eq(reader.stats().cached_bytes, 0)
  assert_eq(
    @archive.Archive::open(arm64_offset_archive).reader().read(1).bytes,
    arm64_tail,
  )
}
