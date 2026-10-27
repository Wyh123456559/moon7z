///|
test "external metadata references flags counts and exact buffer consumption are checked" {
  let names = @utf16.encode("a\u{0000}"[:], bom=false, endianness=Little)
  assert_eq(read_names(Cursor::new(b"\x01\x00"), 1, buffers=[names]), ["a"])
  let times = @buffer.Buffer()
  times.write_uint64_le(1UL)
  times.write_uint64_le(0xffffffffffffffffUL)
  assert_eq(
    read_times(Cursor::new(b"\x00\xa0\x01\x00"), 3, buffers=[times.to_bytes()]),
    [Some(1UL), None, Some(0xffffffffffffffffUL)],
  )
  for
    bad in [
      b"\x02", b"\x01", b"\x01\x01", b"\x01\xff\xff\xff\xff\xff\xff\xff\xff\xff",
    ] {
    let failed = try {
      ignore(read_names(Cursor::new(bad), 1, buffers=[names]))
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(failed)
  }
  let failed = try {
    ignore(
      read_times(Cursor::new(b"\x01\x01\x00"), 1, buffers=[times.to_bytes()]),
    )
    false
  } catch {
    Invalid(..) => true
    _ => false
  }
  assert_true(failed)
  assert_eq(read_names(Cursor::new(b"\x01\x00"), 1, buffers=[names]), ["a"])
}

///|
test "packed metadata and payload intervals reject overlaps gaps and unclaimed suffixes" {
  check_regions([(40, 45), (32, 40)], 45)
  check_regions([(32, 32)], 32)
  for
    regions in [
      [(32, 40), (39, 45)],
      [(33, 40)],
      [(32, 40), (41, 45)],
      [(32, 40)],
    ] {
    let failed = try {
      check_regions(
        regions.map(region => (region.0.to_uint64(), region.1.to_uint64())),
        45,
      )
      false
    } catch {
      Invalid(..) | Unsupported(..) => true
      _ => false
    }
    assert_true(failed)
  }
}

///|
test "encoded header with no folders is empty and invalid multiple outputs are not guessed" {
  let empty = Archive::open(envelope(b"\x17\x00"))
  assert_eq(empty.entries(), [])
  assert_eq(empty.metadata_streams(), [])
  assert_eq(empty.verify().bytes, 0)
  let refused = try {
    ignore(
      Archive::open(
        envelope(
          b"\x17\x06\x00\x02\x09\x01\x01\x00\x07\x0b\x02\x00\x01\x01\x00\x01\x01\x00\x0c\x01\x01\x00\x00",
          packed=b"\x01\x00",
        ),
      ),
    )
    false
  } catch {
    Invalid(..) => true
    _ => false
  }
  assert_true(refused)
}
