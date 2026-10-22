///|
test "every byte interval of a binary member agrees with whole-member reading" {
  let archive = @archive.Archive::open(binary_archive)
  let original = archive.extract_all()[0].bytes
  let reader = archive.reader()
  for offset in 0..<=original.length() {
    for length in 0..<=(original.length() - offset) {
      assert_eq(
        reader.read_range(0, offset~, length~),
        original[offset:offset + length].to_owned(),
      )
    }
  }
  assert_eq(reader.stats().decode_attempts, 1)
}

///|
test "ranges preserve compression filters and solid-member boundaries" {
  for
    bytes in [
      copy_archive, lzma_archive, lzma2_archive, delta_archive, bcj_solid_archive,
      bcj_lzma2_archive,
    ] {
    let archive = @archive.Archive::open(bytes)
    let reader = archive.reader()
    for item in archive.extract_all() {
      if item.entry.kind != File {
        continue
      }
      let id = item.entry.id
      let reconstructed = @buffer.Buffer()
      let mut offset = 0
      while offset < item.bytes.length() {
        let remaining = item.bytes.length() - offset
        let length = if remaining > 257 { 257 } else { remaining }
        reconstructed.write_bytes(reader.read_range(id, offset~, length~))
        offset += length
      }
      assert_eq(reconstructed.to_bytes(), item.bytes)
      assert_eq(reader.read_range(id, offset~, length=0), b"")
    }
  }
}

///|
test "invalid ranges fail before decoding and preserve a checked cache" {
  let reader = @archive.Archive::open(binary_archive).reader()
  for
    (offset, length) in [
      (-1, 0),
      (0, -1),
      (257, 0),
      (256, 1),
      (1, 256),
      (0x7fffffff, 0x7fffffff),
      (1, 0x7fffffff),
    ] {
    assert_true(
      capture(() => reader.read_range(0, offset~, length~))
      is Err(@archive.InvalidRange(..)),
    )
    assert_eq(reader.stats().decode_attempts, 0)
  }
  assert_eq(reader.read_range(0, offset=255, length=1), b"\xff")
  let before = reader.stats()
  assert_true(
    capture(() => reader.read_range(1, offset=0, length=0))
    is Err(@archive.NoSuchEntry(..)),
  )
  assert_true(
    capture(() => reader.read_range(0, offset=256, length=1))
    is Err(@archive.InvalidRange(..)),
  )
  assert_eq(reader.stats(), before)
  let archive = @archive.Archive::open(copy_archive)
  let directory = archive.entries().filter(e => e.kind == Directory)[0].id
  assert_true(
    capture(() => archive.reader().read_range(directory, offset=0, length=0))
    is Err(@archive.Unsupported(..)),
  )
}

///|
test "an empty range still verifies the whole selected folder and recovery works" {
  let changed = copy_archive.to_array()
  changed[32] = (changed[32].to_int() ^ 1).to_byte()
  let archive = @archive.Archive::open(Bytes::from_array(changed))
  let ids = data_ids(archive)
  let reader = archive.reader()
  assert_true(
    capture(() => reader.read_range(ids[0], offset=0, length=0))
    is Err(@archive.Checksum(..)),
  )
  assert_eq(reader.stats().cached_bytes, 0)
  let original = @archive.Archive::open(copy_archive).reader().read(ids[1]).bytes
  assert_eq(
    reader.read_range(ids[1], offset=0, length=original.length()),
    original,
  )
  let uncached = @archive.Archive::open(binary_archive).reader(cache_bytes=0)
  assert_eq(uncached.read_range(0, offset=0, length=1), b"\x00")
  assert_eq(uncached.read_range(0, offset=255, length=1), b"\xff")
  assert_eq(uncached.stats().decode_attempts, 2)
  assert_eq(uncached.stats().cached_bytes, 0)
}
