///|
test "JSON metadata preserves UInt64 maximum zero missing and all attribute bits" {
  let data : Metadata = {
    created: Some(0xffffffffffffffffUL),
    accessed: Some(0UL),
    modified: None,
    attributes: Some(0xffffffffU),
  }
  let document = data.to_json()
  assert_true(
    document
    is {
      "created_filetime": String("18446744073709551615"),
      "accessed_filetime": String("0"),
      "modified_filetime": Null,
      "attributes": Number(4294967295, ..),
      ..
    },
  )
  assert_eq(@json.parse(document.stringify()), document)
}

///|
test "JSON inventory escapes original names and preserves duplicate stable IDs" {
  let name = "目录/\"quoted\"\n\t\\😀"
  let meta : Metadata = {
    created: None,
    accessed: None,
    modified: None,
    attributes: None,
  }
  let entry : Entry = {
    id: 0,
    name,
    kind: File,
    size: 0,
    crc32: Some(1U),
    block: None,
    metadata: meta,
  }
  let document = entry.to_json()
  assert_true(
    document
    is {
      "name": String(original),
      "crc32": String("00000001"),
      "block": Null,
      ..
    } &&
    original == name,
  )
  let text = document.stringify()
  assert_true(text.contains("\\n"))
  assert_true(text.contains("\\t"))
  assert_eq(@json.parse(text), document)
  let duplicate = Archive::open(
    envelope(
      b"\x01\x05\x02\x0e\x01\xc0\x0f\x01\xc0\x11\x09\x00a\x00\x00\x00a\x00\x00\x00\x00\x00",
    ),
  )
  assert_true(
    duplicate.inventory_json()
    is {
      "entries": Array(
        [
          { "id": Number(0, ..), "name": String("a"), .. },
          { "id": Number(1, ..), "name": String("a"), .. },
        ]
      ),
      ..
    },
  )
  assert_eq(
    Archive::open(envelope(b"")).inventory_json().stringify(),
    "{\"schema\":\"moon7z.inventory.v1\",\"contents_verified\":false,\"entries\":[]}",
  )
}
