///|
fn comparison_crc(bytes : Bytes) -> UInt32 {
  let mut crc = 0xffffffffU
  for byte in bytes {
    crc = crc ^ byte.to_uint()
    for _ in 0..<8 {
      crc = (crc >> 1) ^ (if (crc & 1U) != 0U { 0xedb88320U } else { 0U })
    }
  }
  crc ^ 0xffffffffU
}

///|
fn comparison_number(out : @buffer.Buffer, value : UInt64) -> Unit {
  out.write_byte(b'\xff')
  out.write_uint64_le(value)
}

///|
// Project-authored single Copy member / empty-name-list framing. No payload
// CRCs: this deliberately tests exact byte comparison without CRC shortcuts.
fn comparison_fixture(
  bytes : Bytes,
  attributes~ : UInt32 = 32U,
  directory~ : Bool = false,
  names~ : Array[String] = ["item"],
) -> Bytes raise {
  let header = @buffer.Buffer()
  header.write_byte(b'\x01')
  if !bytes.is_empty() {
    assert_eq(names.length(), 1)
    header.write_bytes(b"\x04\x06\x00\x01\x09")
    comparison_number(header, bytes.length().to_uint64())
    header.write_bytes(b"\x00\x07\x0b\x01\x00\x01\x01\x00\x0c")
    comparison_number(header, bytes.length().to_uint64())
    header.write_bytes(b"\x00\x00")
  }
  header.write_byte(b'\x05')
  comparison_number(header, names.length().to_uint64())
  if bytes.is_empty() {
    let bits = if names.length() == 1 { b'\x80' } else { b'\xc0' }
    header.write_bytes(b"\x0e\x01")
    header.write_byte(bits)
    if !directory {
      header.write_bytes(b"\x0f\x01")
      header.write_byte(bits)
    }
  }
  let encoded = @utf16.encode(
    (names.join("\u{0000}") + "\u{0000}")[:],
    bom=false,
    endianness=Little,
  )
  header.write_byte(b'\x11')
  comparison_number(header, encoded.length().to_uint64() + 1UL)
  header.write_byte(b'\x00')
  header.write_bytes(encoded)
  header.write_byte(b'\x15')
  comparison_number(header, 2UL + 4UL * names.length().to_uint64())
  header.write_bytes(b"\x01\x00")
  for _ in names {
    header.write_uint_le(attributes)
  }
  header.write_bytes(b"\x00\x00")
  let fields = @buffer.Buffer()
  fields.write_uint64_le(bytes.length().to_uint64())
  fields.write_uint64_le(header.length().to_uint64())
  fields.write_uint_le(comparison_crc(header.to_bytes()))
  let result = @buffer.Buffer()
  result.write_bytes(b"7z\xbc\xaf\x27\x1c\x00\x04")
  result.write_uint_le(comparison_crc(fields.to_bytes()))
  result.write_bytes(fields.to_bytes())
  result.write_bytes(bytes)
  result.write_bytes(header.to_bytes())
  result.to_bytes()
}

///|
async test "source diff classifies actual bytes metadata type and 64 KiB tail changes without payload CRCs" {
  let left_bytes = comparison_fixture(b"old")
  let left = @archive.SourceArchive::open(memory_input(left_bytes))
  for
    (bytes, kind) in [
      (comparison_fixture(b"new"), @archive.ContentChanged),
      (comparison_fixture(b"old", attributes=33U), @archive.MetadataChanged),
      (
        comparison_fixture(b"new", attributes=33U),
        @archive.ContentAndMetadataChanged,
      ),
      (
        comparison_fixture(b"", directory=true, attributes=16U),
        @archive.TypeChanged,
      ),
    ] {
    let right = @archive.SourceArchive::open(memory_input(bytes))
    let report = left.compare(right)
    assert_eq(report.changes()[0].kind, kind)
    assert_eq(
      report.changes(),
      @archive.Archive::open(left_bytes)
      .compare(@archive.Archive::open(bytes))
      .changes(),
    )
  }
  let first = @archive.SourceArchive::open(
    memory_input(comparison_fixture(b"x".repeat(65536) + b"a")),
  )
  let second = @archive.SourceArchive::open(
    memory_input(comparison_fixture(b"x".repeat(65536) + b"b")),
  )
  assert_eq(first.compare(second).changes()[0].kind, @archive.ContentChanged)
  assert_true(first.compare(first).identical())
}

///|
async test "duplicate source names fail before payload I/O on either side" {
  let bytes = comparison_fixture(b"", names=["same", "same"])
  let duplicate = @archive.SourceArchive::open(memory_input(bytes))
  let good = @archive.SourceArchive::open(
    memory_input(comparison_fixture(b"x")),
  )
  for (a, b) in [(duplicate, good), (good, duplicate)] {
    assert_true(
      try {
        ignore(a.compare(b))
        false
      } catch {
        @archive.AmbiguousName(name="same", first_id=0, second_id=1) => true
        _ => false
      },
    )
  }
}
