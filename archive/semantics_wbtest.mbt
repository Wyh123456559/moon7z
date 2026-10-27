///|
test "start positions retain UInt64 maximum and distinguish absent values" {
  let bytes = @buffer.Buffer()
  bytes.write_bytes(b"\x18\x0a\x01\x00")
  bytes.write_uint64_le(0xffffffffffffffffUL)
  let entry = metadata_entries(bytes.to_bytes())[0]
  assert_eq(entry.metadata.start_position, Some(0xffffffffffffffffUL))
  assert_true(
    entry.to_json()
    is {
      "metadata": { "start_position": String("18446744073709551615"), .. },
      ..
    },
  )
  assert_eq(classify_attributes(Some(0xa1ff0020U)), Regular)
  assert_eq(classify_attributes(Some(0xa1ff8020U)), SymbolicLink)
  assert_eq(classify_attributes(Some(0x40U)), Special)
}

///|
test "anti item masks require declared empty streams and malformed properties do not escape" {
  assert_true(metadata_entries(b"\x10\x01\x80")[0].anti)
  let archive = comparison_archive([
    (
      "a",
      File,
      b"",
      {
        start_position: None,
        created: None,
        accessed: None,
        modified: None,
        attributes: None,
      },
    ),
  ])
  let altered = { ..archive.inventory[0], anti: true, }
  let other = { ..archive, inventory: [altered], }
  assert_eq(archive.compare(other).changes()[0].kind, TypeChanged)
  let linked = {
    ..archive.inventory[0],
    metadata: {
      ..archive.inventory[0].metadata,
      attributes: Some(0xa1ff8020U),
    },
  }
  assert_eq(
    archive.compare({ ..archive, inventory: [linked], }).changes()[0].kind,
    TypeChanged,
  )
  let malformed = try {
    ignore(
      read_files(
        Cursor::new(b"\x01\x10\x01\x80\x00"),
        {
          layouts: [],
          pack_offset: 0,
          pack_sizes: [],
          pack_crcs: [],
          blocks: [],
        },
        Limits::new(),
      ),
    )
    false
  } catch {
    Invalid(..) => true
    _ => false
  }
  assert_true(malformed)
}

///|
test "file property records reject duplicates truncation and policy overflow without losing future reads" {
  for
    bytes in [
      b"\x10\x01\x80\x10\x01\x00", b"\x18\x02\x00\x00\x18\x02\x00\x00", b"\x18\x0a\x01\x00\x00",
      b"\xff", b"\x7f\x04\x00",
    ] {
    let refused = try {
      ignore(metadata_entries(bytes))
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(refused)
    assert_eq(metadata_entries(b"")[0].metadata.start_position, None)
  }
  let limited = try {
    ignore(
      read_files(
        Cursor::new(b"\x00\x7f\x00\x00"),
        {
          pack_offset: 0,
          pack_sizes: [],
          pack_crcs: [],
          blocks: [],
          layouts: [],
        },
        Limits::new(file_property_records=0),
      ),
    )
    false
  } catch {
    Limit(resource="file property records", ..) => true
    _ => false
  }
  assert_true(limited)
}
