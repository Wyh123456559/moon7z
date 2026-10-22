///|
test "empty archives and directories pass the member-checksum policy" {
  assert_eq(
    Archive::open(envelope(b"")).verify(require_member_crcs=true).files,
    0,
  )
  let only_directory = envelope(
    b"\x01\x05\x01\x0e\x01\x80\x11\x05\x00a\x00\x00\x00\x00\x00",
  )
  assert_eq(
    Archive::open(only_directory).verify(require_member_crcs=true).files,
    0,
  )
}

///|
test "a shared solid folder CRC does not masquerade as individual member CRCs" {
  let header = @buffer.Buffer()
  header.write_bytes(
    b"\x01\x04\x06\x00\x01\x09\x06\x00\x07\x0b\x01\x00\x01\x01\x00\x0c\x06\x0a\x01",
  )
  header.write_uint_le(crc32(b"abcdef"))
  header.write_bytes(
    b"\x00\x08\x0d\x02\x09\x03\x00\x00\x05\x02\x11\x09\x00a\x00\x00\x00b\x00\x00\x00\x00\x00",
  )
  let archive = Archive::open(envelope(header.to_bytes(), packed=b"abcdef"))
  assert_eq(archive.verify().members_without_crc, 2)
  let rejected = try {
    ignore(archive.verify(require_member_crcs=true))
    false
  } catch {
    MissingChecksum(id=0, name="a") => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(archive.extract_all().map(item => item.bytes), [b"abc", b"def"])
  let diagnostic = try {
    ignore(archive.verify(require_member_crcs=true))
    ""
  } catch {
    err => err.to_string()
  }
  assert_true(diagnostic.contains("entry 0"))
  assert_true(diagnostic.contains("Repack"))
  let corrupted = envelope(header.to_bytes(), packed=b"xbcdef")
  let damaged = Archive::open(corrupted)
  let missing_first = try {
    ignore(damaged.verify(require_member_crcs=true))
    false
  } catch {
    MissingChecksum(..) => true
    _ => false
  }
  assert_true(missing_first)
  let corrupted_data = try {
    ignore(damaged.verify())
    false
  } catch {
    Checksum(..) => true
    _ => false
  }
  assert_true(corrupted_data)
}
