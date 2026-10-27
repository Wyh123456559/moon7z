///|
test "embedded extent addition rejects UInt64 overflow before narrowing" {
  for
    (offset, size) in [
      (0xffffffffffffffffUL, 0UL),
      (0xffffffffffffffdfUL, 1UL),
      (0UL, 0xffffffffffffffffUL),
      (100000000000UL, 0UL),
    ] {
    let fields = @buffer.Buffer()
    fields.write_uint64_le(offset)
    fields.write_uint64_le(size)
    fields.write_uint_le(0U)
    let header = @buffer.Buffer()
    header.write_bytes(b"7z\xbc\xaf\x27\x1c\x00\x04")
    header.write_uint_le(crc32(fields.to_bytes()[:]))
    header.write_bytes(fields.to_bytes())
    let rejected = try {
      ignore(EmbeddedArchive::open(b"prefix" + header.to_bytes()))
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "last eligible offset empty archive and missing-signature diagnostic are exact" {
  let fields = b"\x00".repeat(20)
  let header = @buffer.Buffer()
  header.write_bytes(b"7z\xbc\xaf\x27\x1c\x00\x04")
  header.write_uint_le(crc32(fields[:]))
  header.write_bytes(fields)
  let input = b"prefix" + header.to_bytes()
  let imported = EmbeddedArchive::open(input)
  assert_eq(imported.prefix, b"prefix")
  assert_eq(imported.archive.entries(), [])
  assert_eq(imported.archive.verify().bytes, 0)
  assert_eq(imported.prefix + imported.payload + imported.suffix, input)
  let diagnostic = SignatureNotFound(searched_bytes=7)
  assert_true(
    diagnostic.to_json()
    is {
      "code": String("signature_not_found"),
      "searched_bytes": Number(7, ..),
      ..
    },
  )
  assert_true(diagnostic.to_string().contains("open_at"))
}
