///|
test "grouped intervals preserve order overlap and duplicates without caching" {
  for
    input in [
      lzma2_archive, delta_archive, bcj_solid_archive, arm64_wrap_archive,
    ] {
    let archive = @archive.Archive::open(input)
    let all = archive.extract_all().filter(item => item.entry.kind == File)
    let requests : Array[@archive.RangeRequest] = []
    let expected : Array[Bytes] = []
    for item in all {
      let size = item.bytes.length()
      let length = if size < 16 { size } else { 16 }
      for offset in [size - length, 0, size - length] {
        requests.push(
          @archive.RangeRequest::new(item.entry.id, offset~, length~),
        )
        expected.push(item.bytes[offset:offset + length].to_owned())
      }
    }
    let reader = archive.reader(cache_bytes=0)
    assert_eq(reader.read_ranges(requests), expected)
    assert_eq(reader.stats().decode_attempts, 1)
    assert_eq(reader.stats().cached_bytes, 0)
  }
}

///|
test "all intervals and aggregate limits are checked before cache changes" {
  let archive = @archive.Archive::open(
    binary_archive,
    limits=@archive.Limits::new(output_bytes=256),
  )
  let reader = archive.reader()
  let first = @archive.RangeRequest::new(0, offset=0, length=1)
  assert_eq(reader.read_ranges([first]), [b"\x00"])
  let before = reader.stats()
  for
    invalid in [
      @archive.RangeRequest::new(-1, offset=0, length=0),
      @archive.RangeRequest::new(0, offset=256, length=1),
      @archive.RangeRequest::new(0, offset=1, length=0x7fffffff),
    ] {
    assert_true(capture(() => reader.read_ranges([first, invalid])) is Err(_))
    assert_eq(reader.stats(), before)
  }
  let whole = @archive.RangeRequest::new(0, offset=0, length=256)
  assert_true(
    capture(() => reader.read_ranges([whole, first])) is Err(@archive.Limit(..)),
  )
  assert_eq(reader.stats(), before)
  assert_eq(reader.read_ranges([whole])[0].length(), 256)
  let limited = @archive.Archive::open(
    binary_archive,
    limits=@archive.Limits::new(entries=1),
  ).reader()
  assert_true(
    capture(() => limited.read_ranges([first, first]))
    is Err(@archive.Limit(..)),
  )
  assert_eq(limited.stats().decode_attempts, 0)
  assert_eq(reader.read_ranges([]), [])
}

///|
test "bulk intervals group interleaved independent folders without changing output order" {
  let archive = @archive.Archive::open(separate_archive)
  let ids = data_ids(archive)
  let order = [ids[3], ids[0], ids[3], ids[1], ids[2], ids[0]]
  let requests = order.map(id => {
    @archive.RangeRequest::new(id, offset=0, length=1)
  })
  let all = archive.extract_all()
  let reader = archive.reader(cache_bytes=0)
  assert_eq(
    reader.read_ranges(requests),
    order.map(id => all[id].bytes[:1].to_owned()),
  )
  assert_eq(reader.stats().decode_attempts, 4)
  assert_eq(reader.stats().cache_hits, 0)
}

///|
test "bulk ranges check complete selected folders including zero-length ranges" {
  let changed = copy_archive.to_array()
  changed[32] = (changed[32].to_int() ^ 1).to_byte()
  let archive = @archive.Archive::open(Bytes::from_array(changed))
  let ids = data_ids(archive)
  let reader = archive.reader(cache_bytes=0)
  let bad = @archive.RangeRequest::new(ids[0], offset=0, length=0)
  assert_true(
    capture(() => reader.read_ranges([bad])) is Err(@archive.Checksum(..)),
  )
  assert_eq(reader.stats().cached_bytes, 0)
  let good = @archive.RangeRequest::new(ids[1], offset=0, length=1)
  let original = @archive.Archive::open(copy_archive)
    .reader()
    .read_range(ids[1], offset=0, length=1)
  assert_eq(reader.read_ranges([good, good]), [original, original])
  assert_eq(reader.stats().decode_attempts, 2)
  let directory = archive.entries().filter(e => e.kind == Directory)[0].id
  assert_true(
    capture(() => {
      reader.read_ranges([
        @archive.RangeRequest::new(directory, offset=0, length=0),
      ])
    })
    is Err(@archive.Unsupported(..)),
  )
}
