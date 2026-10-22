///|
test "binary selection preserves all 256 byte values" {
  let archive = @archive.Archive::open(binary_archive)
  assert_eq(archive.reader().read(0).bytes, Bytes::makei(256, i => i.to_byte()))
}

///|
fn data_ids(archive : @archive.Archive) -> Array[Int32] {
  archive
  .entries()
  .filter(entry => entry.block is Some(_))
  .map(entry => entry.id)
}

///|
test "selective reads reproduce each member and reuse a solid folder" {
  let archive = @archive.Archive::open(lzma2_archive)
  let all = archive.extract_all()
  let reader = archive.reader()
  for id in data_ids(archive) {
    assert_eq(reader.read(id), all[id])
  }
  assert_eq(reader.stats().decode_attempts, 1)
  assert_eq(reader.stats().cache_hits, 3)
  assert_eq(reader.stats().cached_bytes, 14550)
  let before = reader.stats()
  let rejected = try {
    ignore(reader.read_many([data_ids(archive)[0], -1]))
    false
  } catch {
    @archive.NoSuchEntry(..) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(reader.stats(), before)
  reader.clear_cache()
  assert_eq(reader.stats().cached_bytes, 0)
  assert_eq(reader.stats().decode_attempts, 1)
  let id = data_ids(archive)[0]
  assert_eq(reader.read(id), all[id])
  assert_eq(reader.stats().decode_attempts, 2)
}

///|
test "grouped reads decode each selected folder once and preserve request order" {
  let archive = @archive.Archive::open(separate_archive)
  let ids = data_ids(archive)
  let request = [ids[0], ids[1], ids[0], ids[2], ids[1], ids[3]]
  let reader = archive.reader(cache_bytes=0)
  let selected = reader.read_many(request)
  let all = archive.extract_all()
  assert_eq(selected.map(item => item.entry.id), request)
  for i, id in request {
    assert_eq(selected[i], all[id])
  }
  assert_eq(reader.stats().decode_attempts, 4)
  assert_eq(reader.stats().cache_hits, 0)
  assert_eq(reader.stats().cached_bytes, 0)
}

///|
test "cache budget never retains an oversized folder" {
  let archive = @archive.Archive::open(lzma_archive)
  let id = data_ids(archive)[0]
  for budget in [0, 14549] {
    let reader = archive.reader(cache_bytes=budget)
    assert_eq(reader.read(id), reader.read(id))
    assert_eq(reader.stats().decode_attempts, 2)
    assert_eq(reader.stats().cached_bytes, 0)
  }
  let reader = archive.reader(cache_bytes=14550)
  ignore(reader.read(id))
  assert_eq(reader.stats().cached_bytes, 14550)
  let rejected = try {
    ignore(archive.reader(cache_bytes=-1))
    false
  } catch {
    @archive.Invalid(..) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid IDs and duplicate expansion limits fail before decoding" {
  let archive = @archive.Archive::open(lzma2_archive)
  let reader = archive.reader()
  let id = data_ids(archive)[0]
  for ids in [[id, -1], [id, archive.entries().length()]] {
    let rejected = try {
      ignore(reader.read_many(ids))
      false
    } catch {
      @archive.NoSuchEntry(..) => true
      _ => false
    }
    assert_true(rejected)
    assert_eq(reader.stats().decode_attempts, 0)
  }
  let limited = @archive.Archive::open(
    lzma2_archive,
    limits=@archive.Limits::new(output_bytes=14550),
  ).reader()
  let rejected = try {
    ignore(limited.read_many([id, id]))
    false
  } catch {
    @archive.Limit(..) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(limited.stats().decode_attempts, 0)
  assert_eq(reader.read_many([]), [])
  assert_eq(reader.stats().decode_attempts, 0)
}

///|
test "empty members and directories need no data decode" {
  let archive = @archive.Archive::open(copy_archive)
  let reader = archive.reader()
  let empty = archive
    .entries()
    .filter(entry => entry.block is None)
    .map(entry => entry.id)
  assert_eq(empty.length(), 3)
  for item in reader.read_many(empty) {
    assert_eq(item.bytes, b"")
  }
  assert_eq(reader.stats().decode_attempts, 0)
  assert_eq(reader.stats().cached_bytes, 0)
}

///|
test "selective verification excludes unrelated folders and recovers after failure" {
  let changed = copy_archive.to_array()
  changed[32] = (changed[32].to_int() ^ 1).to_byte()
  let archive = @archive.Archive::open(Bytes::from_array(changed))
  let ids = data_ids(archive)
  let reader = archive.reader()
  let healthy = reader.read(ids[1])
  assert_true(healthy.bytes.length() > 0)
  for _ in 0..<2 {
    let rejected = try {
      ignore(reader.read(ids[0]))
      false
    } catch {
      @archive.Checksum(..) => true
      _ => false
    }
    assert_true(rejected)
    assert_eq(reader.stats().cached_bytes, 0)
  }
  assert_eq(reader.stats().decode_attempts, 3)
  assert_eq(reader.read(ids[1]), healthy)
  let rejected = try {
    ignore(archive.verify())
    false
  } catch {
    @archive.Checksum(..) => true
    _ => false
  }
  assert_true(rejected)
}
