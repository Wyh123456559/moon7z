///|
test "JSON inventory retains original order names sizes CRCs and metadata" {
  for bytes in [copy_archive, lzma2_archive, delta_archive, bcj_lzma2_archive] {
    let archive = @archive.Archive::open(bytes)
    let document = archive.inventory_json()
    guard document
      is {
        "schema": String("moon7z.inventory.v1"),
        "contents_verified": False,
        "entries": Array(entries),
        ..
      } else {
      fail("invalid inventory envelope")
    }
    let original = archive.entries()
    assert_eq(entries.length(), original.length())
    for i, item in entries {
      assert_eq(item, original[i].to_json())
      guard item
        is {
          "id": Number(id, ..),
          "name": String(name),
          "size": Number(size, ..),
          "metadata": Object(_),
          ..
        } else {
        fail("invalid member")
      }
      assert_eq(id, i.to_double())
      assert_eq(name, original[i].name)
      assert_eq(size, original[i].size.to_double())
    }
    let text = document.stringify()
    assert_eq(@json.parse(text), document)
    assert_eq(text, archive.inventory_json().stringify())
    // The JSON data is detached; mutation cannot affect subsequent reports.
    entries.clear()
    assert_eq(archive.entries().length(), original.length())
    assert_eq(archive.inventory_json().stringify(), text)
  }
}

///|
test "JSON verification distinguishes missing CRCs and has stable exact output" {
  let archive = @archive.Archive::open(copy_archive)
  let document = archive.verify().to_json()
  assert_eq(
    document.stringify(),
    "{\"schema\":\"moon7z.verification.v1\",\"contents_verified\":true,\"files\":5,\"bytes\":14550,\"blocks\":4,\"member_crcs_checked\":4,\"members_without_crc\":1}",
  )
  assert_eq(@json.parse(document.stringify()), document)
  let report = @archive.Archive::open(binary_archive)
    .verify(require_member_crcs=true)
    .to_json()
  assert_true(
    report
    is {
      "contents_verified": True,
      "files": Number(1, ..),
      "members_without_crc": Number(0, ..),
      ..
    },
  )
  // Listing is header-only even after a separate verify call.
  assert_true(archive.inventory_json() is { "contents_verified": False, .. })
}

///|
test "JSON listing never implies verification of damaged payloads" {
  let healthy = @archive.Archive::open(binary_archive).inventory_json()
  assert_true(
    healthy
    is {
      "entries": Array(
        [{ "crc32": String("29058c73"), "kind": String("file"), .. }]
      ),
      ..
    },
  )
  let changed = binary_archive.to_array()
  changed[32] = b'\xff'
  let archive = @archive.Archive::open(Bytes::from_array(changed))
  assert_true(
    archive.inventory_json()
    is { "contents_verified": False, "entries": Array([_]), .. },
  )
  assert_true(capture(() => archive.verify()) is Err(@archive.Checksum(..)))
}
