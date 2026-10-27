///|
test "UInt64 source intervals header extents and region ordering do not narrow or wrap" {
  validate_source_range(0xffffffffffffffffUL, 0xfffffffffffffffeUL, 1)
  validate_source_range(0xffffffffffffffffUL, 0xffffffffffffffffUL, 0)
  let limits = Limits::new()
  assert_eq(
    source_header_range(0x100000080UL, 0x100000000UL, 96UL, limits),
    (0x100000020UL, 96),
  )
  check_regions(
    [(0x100000000UL, 0x100000001UL), (32UL, 0x100000000UL)],
    0x100000001UL,
  )
  for
    (size, offset, length) in [
      (0xffffffffffffffffUL, 0xffffffffffffffffUL, 1),
      (10UL, 11UL, 0),
      (10UL, 0UL, -1),
      (10UL, 9UL, 2),
      (0xffffffffffffffffUL, 0UL, 0x40000000),
    ] {
    let failed = try {
      validate_source_range(size, offset, length)
      false
    } catch {
      SourceRead(..) => true
      _ => false
    }
    assert_true(failed)
  }
  for
    (size, offset, length) in [
      (31UL, 0UL, 0UL),
      (0xffffffffffffffffUL, 0xffffffffffffffffUL, 1UL),
      (0xffffffffffffffffUL, 0xffffffffffffffdfUL, 1UL),
      (100UL, 1UL, 1UL),
    ] {
    let failed = try {
      ignore(source_header_range(size, offset, length, limits))
      false
    } catch {
      SourceRead(..) => true
      _ => false
    }
    assert_true(failed)
  }
  let error = SourceRead(offset=0xffffffffffffffffUL, reason="test")
  assert_true(
    error.to_json() is { "offset": String("18446744073709551615"), .. },
  )
  let limit = SourceLimit(resource="test", maximum=0xffffffffffffffffUL)
  assert_true(
    limit.to_json() is { "maximum": String("18446744073709551615"), .. },
  )
}

///|
test "source composition rejects count and UInt64 length overflow before I/O" {
  let maximum = SeekableInput::new(0xffffffffffffffffUL, (_, _) => b"")
  let one = SeekableInput::new(1UL, (_, _) => b"")
  assert_true(
    try {
      ignore(SeekableInput::concat([maximum, one]))
      false
    } catch {
      SourceRead(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(SeekableInput::concat([]))
      false
    } catch {
      SourceRead(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(SeekableInput::concat([one, one], max_parts=1))
      false
    } catch {
      Limit(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(SeekableInput::concat([one], max_parts=0))
      false
    } catch {
      Invalid(..) => true
      _ => false
    },
  )
  let report : SourceVerification = {
    files: 1,
    bytes: 0xffffffffffffffffUL,
    blocks: 1,
    member_crcs_checked: 1,
    members_without_crc: 0,
  }
  assert_true(
    report.to_json() is { "bytes": String("18446744073709551615"), .. },
  )
}
