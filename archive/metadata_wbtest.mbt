///|
fn metadata_entries(properties : Bytes) -> Array[Entry] raise ArchiveError {
  let r = Cursor::new(
    b"\x01\x0e\x01\x80\x0f\x01\x80\x11\x05\x00a\x00\x00\x00" +
    properties +
    b"\x00",
  )
  read_files(
    r,
    { pack_offset: 0, pack_sizes: [], pack_crcs: [], blocks: [], layouts: [], },
    Limits::new(),
  )
}

///|
test "optional metadata retains all FILETIME bits and raw attributes" {
  let properties = @buffer.Buffer()
  for (id, value) in [(18, 1UL), (19, 0UL), (20, 0xffffffffffffffffUL)] {
    properties.write_byte(id.to_byte())
    properties.write_byte(b'\x0a')
    properties.write_bytes(b"\x01\x00")
    properties.write_uint64_le(value)
  }
  properties.write_bytes(b"\x15\x06\x01\x00")
  properties.write_uint_le(0x81a40020U)
  let entry = metadata_entries(properties.to_bytes())[0]
  assert_eq(entry.metadata.created, Some(1UL))
  assert_eq(entry.metadata.accessed, Some(0UL))
  assert_eq(entry.metadata.modified, Some(0xffffffffffffffffUL))
  assert_eq(entry.metadata.attributes, Some(0x81a40020U))
  assert_eq(entry.kind, File)
}

///|
test "links and special metadata remain readable while restoration and malformed references are refused" {
  for
    (attr, semantics) in [
      (0xa1ff8020U, SymbolicLink),
      (0x11a48020U, Special),
      (0x420U, ReparsePoint),
    ] {
    let properties = @buffer.Buffer()
    properties.write_bytes(b"\x15\x06\x01\x00")
    properties.write_uint_le(attr)
    let entries = metadata_entries(properties.to_bytes())
    assert_eq(entries[0].semantics(), semantics)
    let refused = try {
      ignore(plan_entries(entries))
      false
    } catch {
      UnsafePath(..) => true
      _ => false
    }
    assert_true(refused)
  }
  let refused = try {
    ignore(metadata_entries(b"\x14\x02\x01\x01"))
    false
  } catch {
    Invalid(..) => true
    _ => false
  }
  assert_true(refused)
}
