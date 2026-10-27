///|
test "source SFX signature discovery respects candidate bounds and start CRC" {
  let empty = b"7z\xbc\xaf\x27\x1c\x00\x04\x8d\x9b\xd5\x0f" + b"\x00".repeat(20)
  assert_eq(find_source_signature(b"prefix" + empty, 6), None)
  assert_eq(find_source_signature(b"prefix" + empty, 7), Some(6))
  let decoy = empty.to_array()
  decoy[8] = decoy[8] ^ b'\x01'
  assert_eq(
    find_source_signature(Bytes::from_array(decoy) + empty, 33),
    Some(32),
  )
  assert_eq(source_embedded_extent(empty, 0UL, 32UL, Limits::new()), 32UL)
}

///|
test "source SFX UInt64 extent arithmetic and view bounds reject overflow before I/O" {
  for
    (next_offset, next_size) in [
      (0xffffffffffffffffUL, 0UL),
      (0xffffffffffffffdfUL, 1UL),
      (0UL, 0xffffffffffffffffUL),
    ] {
    let fields = @buffer.Buffer()
    fields.write_uint64_le(next_offset)
    fields.write_uint64_le(next_size)
    fields.write_uint_le(0U)
    let header = @buffer.Buffer()
    header.write_bytes(b"7z\xbc\xaf\x27\x1c\x00\x04")
    header.write_uint_le(crc32(fields.to_bytes()[:]))
    header.write_bytes(fields.to_bytes())
    let rejected = try {
      ignore(
        source_embedded_extent(
          header.to_bytes(),
          0x100000000UL,
          0xffffffffffffffffUL,
          Limits::new(),
        ),
      )
      false
    } catch {
      SourceRead(..) => true
      _ => false
    }
    assert_true(rejected)
  }
  let source = SeekableInput::new(0xffffffffffffffffUL, (_, _) => b"")
  assert_eq(source.slice(0xffffffffffffffffUL, 0UL).size, 0UL)
  assert_eq(source.slice(0xfffffffffffffffeUL, 1UL).size, 1UL)
  assert_true(
    try {
      ignore(source.slice(0xffffffffffffffffUL, 1UL))
      false
    } catch {
      SourceRead(..) => true
      _ => false
    },
  )
  let error = SourceSignatureNotFound(searched_bytes=0xffffffffffffffffUL)
  assert_true(
    error.to_json() is { "searched_bytes": String("18446744073709551615"), .. },
  )
  assert_true(error.to_string().contains("open_at"))
}
