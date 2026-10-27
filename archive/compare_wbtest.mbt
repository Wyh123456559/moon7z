///|
fn comparison_archive(
  items : Array[(String, EntryKind, Bytes, Metadata)],
) -> Archive {
  let input = @buffer.Buffer()
  input.write_bytes(b"x".repeat(32))
  let blocks : Array[Block] = []
  let sizes : Array[Int32] = []
  let inventory = items.mapi((id, item) => {
    let (name, kind, bytes, metadata) = item
    let block = if kind == File && !bytes.is_empty() {
      let number = blocks.length()
      blocks.push({
        coders: [{ codec_id: b"\x00", properties: b"", }],
        size: bytes.length(),
        crc: None,
        pieces: [(bytes.length(), None)],
      })
      sizes.push(bytes.length())
      input.write_bytes(bytes)
      Some(number)
    } else {
      None
    }
    { id, name, kind, size: bytes.length(), crc32: None, block, metadata, }
  })
  {
    input: input.to_bytes(),
    limits: Limits::new(),
    archive_properties: [],
    auxiliary: [],
    crypto: CryptState::new(None, Limits::new()),
    inventory,
    streams: {
      layouts: [],
      pack_offset: 0,
      pack_sizes: sizes,
      pack_crcs: sizes.map(_ => None),
      blocks,
    },
  }
}

///|
test "comparison distinguishes content metadata both and type changes without CRC shortcuts" {
  let meta : Metadata = {
    created: None,
    accessed: None,
    modified: None,
    attributes: None,
  }
  let new_meta : Metadata = {
    created: Some(0xffffffffffffffffUL),
    accessed: Some(0UL),
    modified: None,
    attributes: Some(32U),
  }
  let left = comparison_archive([
    ("removed", File, b"gone", meta),
    ("bytes", File, b"old", meta),
    ("meta", File, b"same", meta),
    ("both", File, b"old", meta),
    ("type", File, b"x", meta),
    ("same", Directory, b"", meta),
  ])
  let right = comparison_archive([
    ("added", File, b"new", meta),
    ("bytes", File, b"new", meta),
    ("meta", File, b"same", new_meta),
    ("both", File, b"new", new_meta),
    ("type", Directory, b"", meta),
    ("same", Directory, b"", meta),
  ])
  let changes = left.compare(right).changes()
  assert_eq(changes.map(change => change.name), [
    "added", "both", "bytes", "meta", "removed", "type",
  ])
  assert_eq(changes.map(change => change.kind), [
    Added,
    ContentAndMetadataChanged,
    ContentChanged,
    MetadataChanged,
    Removed,
    TypeChanged,
  ])
  assert_true(
    changes[3].to_json()
    is {
      "right": {
        "metadata": { "created_filetime": String("18446744073709551615"), .. },
        ..
      },
      ..
    },
  )
  assert_eq(right.compare(left).changes().map(change => change.kind), [
    Removed,
    ContentAndMetadataChanged,
    ContentChanged,
    MetadataChanged,
    Added,
    TypeChanged,
  ])
}

///|
test "comparison refuses ambiguous names on either side and preserves exact Unicode names" {
  let duplicate = named_empty_archive(["same", "same"])
  let empty = named_empty_archive([])
  for (a, b) in [(duplicate, empty), (empty, duplicate)] {
    let rejected = try {
      ignore(a.compare(b))
      false
    } catch {
      AmbiguousName(name="same", first_id=0, second_id=1) => true
      _ => false
    }
    assert_true(rejected)
  }
  assert_true(empty.compare(empty).identical())
  let left = named_empty_archive(["目录", "A", "../inspect-only"])
  let right = named_empty_archive(["目录", "a", "../inspect-only"])
  assert_eq(left.compare(right).changes().map(change => change.name), ["A", "a"])
}
