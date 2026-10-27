///|
test "folderwise verification checks member CRCs when no folder CRC exists" {
  let input = b"x".repeat(32) + b"abcdef"
  let second_crc = crc32(b"def") ^ 1U
  let block : Block = {
    coders: [{ codec_id: b"\x00", properties: b"", }],
    size: 6,
    crc: None,
    pieces: [(3, Some(crc32(b"abc"))), (3, Some(second_crc))],
  }
  let archive : Archive = {
    input,
    limits: Limits::new(),
    archive_properties: [],
    auxiliary: [],
    file_extensions: [],
    crypto: CryptState::new(None, Limits::new()),
    streams: {
      layouts: [],
      pack_offset: 0,
      pack_sizes: [6],
      pack_crcs: [None],
      blocks: [block],
    },
    inventory: ["first", "second"].mapi((id, name) => {
      anti: false,
      id,
      name,
      kind: File,
      size: 3,
      block: Some(0),
      crc32: Some(if id == 0 { crc32(b"abc") } else { second_crc }),
      metadata: {
        start_position: None,
        created: None,
        accessed: None,
        modified: None,
        attributes: None,
      },
    }),
  }
  let scope = try {
    ignore(archive.verify())
    ""
  } catch {
    Checksum(scope~) => scope
    _ => "unexpected error"
  }
  assert_eq(scope, "member second")
  let previous_scope = try {
    ignore(archive.extract_all())
    ""
  } catch {
    Checksum(scope~) => scope
    _ => "unexpected error"
  }
  assert_eq(scope, previous_scope)
}
