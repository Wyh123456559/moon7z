///|
test "filename count is enforced before accumulating extra strings" {
  let rejected = try {
    ignore(read_names(Cursor::new(b"\x00a\x00\x00\x00b\x00\x00\x00"), 1))
    false
  } catch {
    Invalid(..) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "a bad sibling CRC prevents returning or caching a selected solid folder" {
  let block : Block = {
    coders: [{ codec_id: b"\x00", properties: b"", }],
    size: 6,
    crc: None,
    pieces: [(3, Some(crc32(b"abc"))), (3, Some(crc32(b"def") ^ 1U))],
  }
  let archive : Archive = {
    input: b"x".repeat(32) + b"abcdef",
    limits: Limits::new(),
    archive_properties: [],
    auxiliary: [],
    crypto: CryptState::new(None, Limits::new()),
    streams: {
      layouts: [],
      pack_offset: 0,
      pack_sizes: [6],
      pack_crcs: [None],
      blocks: [block],
    },
    inventory: ["first", "second"].mapi((id, name) => {
      id,
      name,
      kind: File,
      size: 3,
      crc32: Some(if id == 0 { crc32(b"abc") } else { crc32(b"def") ^ 1U }),
      block: Some(0),
      metadata: {
        created: None,
        accessed: None,
        modified: None,
        attributes: None,
      },
    }),
  }
  let reader = archive.reader()
  let rejected = try {
    ignore(reader.read(0))
    false
  } catch {
    Checksum(..) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(reader.stats().decode_attempts, 1)
  assert_eq(reader.stats().cached_bytes, 0)
}
