///|
fn encoded_number(value : UInt64) -> Bytes {
  let out = @buffer.Buffer()
  out.write_byte(b'\xff')
  out.write_uint64_le(value)
  out.to_bytes()
}

///|
fn envelope(header : Bytes, packed~ : Bytes = b"") -> Bytes {
  let start = @buffer.Buffer()
  start.write_uint64_le(packed.length().to_uint64())
  start.write_uint64_le(header.length().to_uint64())
  start.write_uint_le(crc32(header))
  let out = @buffer.Buffer()
  out.write_bytes(b"7z\xbc\xaf\x27\x1c\x00\x04")
  out.write_uint_le(crc32(start.to_bytes()))
  out.write_bytes(start.to_bytes())
  out.write_bytes(packed)
  out.write_bytes(header)
  out.to_bytes()
}

///|
test "CRC-32 IEEE known vectors" {
  assert_eq(crc32(b""), 0U)
  assert_eq(crc32(b"123456789"), 0xcbf43926U)
}

///|
test "all variable integer widths including UInt64 maximum" {
  for
    value in [
      0UL, 127UL, 128UL, 16383UL, 16384UL, 0x100000000UL, 0xffffffffffffffffUL,
    ] {
    assert_eq(Cursor::new(encoded_number(value)).number(), value)
  }
  for
    (data, value) in [
      (b"\x7f", 127UL),
      (b"\x80\x80", 128UL),
      (b"\xc0\x00\x40", 16384UL),
    ] {
    assert_eq(Cursor::new(data).number(), value)
  }
  for length in 1..<9 {
    let failed = try {
      ignore(
        Cursor::new(encoded_number(0xffffffffffffffffUL)[:length].to_owned()).number(),
      )
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}

///|
test "empty archive and no silent unknown properties" {
  let empty = Archive::open(envelope(b""))
  assert_eq(empty.extract_all().length(), 0)
  assert_eq(empty.verify().files, 0)
  assert_eq(
    Archive::open(envelope(b"\x01\x05\x00\x00\x00")).entries().length(),
    0,
  )
  for header in [b"\x01\x06\x00", b"\x01\x05\x00\x16\x00\x00\x00"] {
    let error = try {
      ignore(Archive::open(envelope(header)))
      None
    } catch {
      err => Some(err)
    }
    assert_true(error is Some(Unsupported(..)))
  }
}

///|
test "substream counts and properties cannot escape their boundaries" {
  for
    header in [
      b"\x01\x05\x01\x00\x00", b"\x01\x05\xff\xff\xff\xff\xff\xff\xff\xff\xff", b"\x01\x05\x01\x11\x04\x00\x61\x00\x00\x00\x00",
      b"\x01\x05\x01\x11\x03\x00\x00\xd8\x00\x00",
    ] {
    let rejected = try {
      ignore(Archive::open(envelope(header)))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "LZMA2 expanded size is bounded before codec allocation" {
  for
    (packed, expected) in [
      (b"\x01\xff\xff", 1),
      (b"\xe0\x1f\xff\x00\x00\x5d", 1),
      (b"\x00x", 0),
      (b"\x00", 1),
      (b"\x03\x00", 0),
    ] {
    let rejected = try {
      preflight_lzma2(packed, expected)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  preflight_lzma2(b"\x01\x00\x00A\x00", 1)
}

///|
test "unsupported methods and huge dictionaries fail without decoding" {
  let unsupported = try {
    validate_coder({ codec_id: b"\x06\xf1\x07\x02", properties: b"", })
    false
  } catch {
    Unsupported(..) => true
    _ => false
  }
  assert_true(unsupported)
  let huge = { codec_id: b"\x21", properties: b"\x28", }
  validate_coder(huge)
  assert_eq(dictionary(huge), 0xffffffffUL)
  let rejected = try {
    validate_dictionary(huge, Limits::new())
    false
  } catch {
    Limit(..) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "raw LZMA is bounded by the container length" {
  let props = b"\x5d\x00\x10\x00\x00"
  let block : Block = {
    coders: [{ codec_id: b"\x03\x01\x01", properties: props, }],
    size: 100,
    crc: None,
    pieces: [],
  }
  let rejected = try {
    ignore(decode(block, b"\x00", Limits::new()))
    false
  } catch {
    Codec(..) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "duplicate names remain distinct stable members in memory" {
  let header = b"\x01\x05\x02\x0e\x01\xc0\x0f\x01\xc0\x11\x09\x00a\x00\x00\x00a\x00\x00\x00\x00\x00"
  let archive = Archive::open(envelope(header))
  let items = archive.extract_all()
  assert_eq(items.length(), 2)
  assert_eq(items[0].entry.name, "a")
  assert_eq(items[1].entry.name, "a")
  assert_eq(items[0].entry.id, 0)
  assert_eq(items[1].entry.id, 1)
}
