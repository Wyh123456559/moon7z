///|
fn arm64_block(properties : Bytes, size : Int32) -> Block {
  {
    coders: [
      { codec_id: b"\x00", properties: b"", },
      { codec_id: b"\x0a", properties, },
    ],
    size,
    crc: None,
    pieces: [],
  }
}

///|
test "7-Zip offset fixtures carry and retain the requested ARM64 properties" {
  for
    (input, expected) in [
      (arm64_offset_resource, 4096U),
      (arm64_wrap_resource, 0xfffffffcU),
    ] {
    let archive = Archive::open(input)
    let filter = archive.streams.blocks[0].coders[1]
    assert_eq(filter.codec_id, b"\x0a")
    assert_eq(filter.properties.length(), 4)
    assert_eq(Cursor::new(filter.properties).u32(), expected)
  }
}

///|
test "ARM64 BL ADRP and wrapping arithmetic match independent instruction vectors" {
  assert_eq(
    decode(
      arm64_block(b"", 8),
      b"\x1f\x20\x03\xd5\x05\x00\x00\x94",
      Limits::new(),
    ),
    b"\x1f\x20\x03\xd5\x04\x00\x00\x94",
  )
  let page = b"\x00\x10\x00\x00"
  assert_eq(
    decode(arm64_block(page, 4), b"\x05\x04\x00\x94", Limits::new()),
    b"\x05\x00\x00\x94",
  )
  assert_eq(
    decode(arm64_block(page, 4), b"\x00\x00\x00\xb0", Limits::new()),
    b"\x00\x00\x00\x90",
  )
  assert_eq(
    decode(
      arm64_block(b"\xfc\xff\xff\xff", 4),
      b"\x00\x00\x00\x94",
      Limits::new(),
    ),
    b"\x01\x00\x00\x94",
  )
  for bytes in [b"\x00\x00\x10\x90", b"\x00\x00\x00\x14", b"\x1f\x20\x03\xd5"] {
    assert_eq(decode(arm64_block(page, 4), bytes, Limits::new()), bytes)
  }
  for length in 0..<4 {
    let bytes = b"\xaa\xbb\xcc"[:length].to_owned()
    assert_eq(
      decode(arm64_block(b"", length), bytes, Limits::new(dictionary_bytes=0)),
      bytes,
    )
  }
}

///|
test "ARM64 property shape and alignment are checked before decode" {
  for properties in [b"", b"\x00\x00\x00\x00", b"\xfc\xff\xff\xff"] {
    let coder : Coder = { codec_id: b"\x0a", properties, }
    validate_coder(coder)
    assert_eq(dictionary(coder), 0UL)
  }
  for
    properties in [
      b"\x00", b"\x00\x00", b"\x00\x00\x00", b"\x00\x00\x00\x00\x00", b"\x01\x00\x00\x00",
      b"\x02\x00\x00\x00", b"\x03\x00\x00\x00",
    ] {
    let rejected = try {
      validate_coder({ codec_id: b"\x0a", properties, })
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(rejected)
  }
  let pipeline = read_pipeline(
    Cursor::new(b"\x02\x21\x0a\x04\x00\x10\x00\x00\x01\x00\x00\x01"),
  )
  assert_eq(pipeline[0].codec_id, b"\x00")
  assert_eq(pipeline[1].properties, b"\x00\x10\x00\x00")
}

///|
test "ARM64 composes with Delta in the resolved decode order" {
  let intermediate = b"\x1f\x20\x03\xd5\x05\x00\x00\x94"
  let packed = Bytes::makei(8, i => {
    let previous = if i == 0 { 0 } else { intermediate[i - 1].to_int() }
    ((intermediate[i].to_int() - previous) & 255).to_byte()
  })
  let block : Block = {
    coders: read_pipeline(
      Cursor::new(b"\x03\x01\x00\x21\x03\x01\x00\x01\x0a\x01\x00\x02\x01"),
    ),
    size: 8,
    crc: Some(crc32(b"\x1f\x20\x03\xd5\x04\x00\x00\x94")),
    pieces: [],
  }
  assert_eq(
    decode(block, packed, Limits::new()),
    b"\x1f\x20\x03\xd5\x04\x00\x00\x94",
  )
}

///|
test "invalid ARM64 properties are refused while opening a complete archive" {
  for
    properties in [
      b"\x00", b"\x00\x00\x00", b"\x03\x00\x00\x00", b"\x00\x00\x00\x00\x00",
    ] {
    let header = @buffer.Buffer()
    header.write_bytes(
      b"\x01\x04\x06\x00\x01\x09\x01\x00\x07\x0b\x01\x00\x02\x01\x00\x21\x0a",
    )
    header.write_byte(properties.length().to_byte())
    header.write_bytes(properties)
    header.write_bytes(
      b"\x01\x00\x0c\x04\x04\x00\x00\x05\x01\x11\x05\x00a\x00\x00\x00\x00\x00",
    )
    let reason = try {
      ignore(Archive::open(envelope(header.to_bytes(), packed=b"x")))
      ""
    } catch {
      Invalid(reason~, ..) => reason
      _ => "unexpected"
    }
    assert_true(reason.contains("ARM64"))
  }
}
