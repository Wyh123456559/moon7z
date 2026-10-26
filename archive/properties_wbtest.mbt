///|
test "archive properties preserve ordering duplicate IDs empty data and arbitrary bytes" {
  let bytes = envelope(
    b"\x01\x02\x80\x80\x04\x00\xffA\n\x80\xff\x00\x80\x80\x01x\x00\x00",
  )
  let archive = Archive::open(bytes)
  assert_eq(archive.properties(), [
    { id: 128UL, data: b"\x00\xffA\n", },
    { id: 255UL, data: b"", },
    { id: 128UL, data: b"x", },
  ])
  let detached = archive.properties()
  detached.clear()
  assert_eq(archive.properties().length(), 3)
  let json = archive.inventory_json()
  assert_true(
    json
    is {
      "archive_properties": Array(
        [
          { "id": String("128"), "data_base64": String("AP9BCg=="), .. },
          { "id": String("255"), "data_base64": String(""), .. },
          { "id": String("128"), "data_base64": String("eA=="), .. },
        ]
      ),
      ..
    },
  )
  assert_eq(@json.parse(json.stringify()), json)
  assert_eq(@base64.decode("AP9BCg=="), archive.properties()[0].data)
  assert_eq(archive.verify().files, 0)
  assert_eq(archive.extract_all(), [])
  assert_true(
    Archive::open(envelope(b"\x01\x02\x00\x00")).properties().is_empty(),
  )
  let maximum = Archive::open(
    envelope(
      b"\x01\x02" + encoded_number(0xffffffffffffffffUL) + b"\x00\x00\x00",
    ),
  )
  assert_eq(maximum.properties()[0].id, 0xffffffffffffffffUL)
  assert_true(
    maximum.properties()[0].to_json()
    is { "id": String("18446744073709551615"), .. },
  )
}

///|
test "archive property record and byte budgets reject malformed data before results" {
  for
    header in [
      b"\x01\x02", b"\x01\x02\x80", b"\x01\x02\x80\x04a\x00\x00", b"\x01\x02\x80\xff\xff\xff\xff\xff\xff\xff\xff\xff\x00\x00",
      b"\x01\x02\x00", b"\x01\x02\x80\x00\x00\x02\x00\x00",
    ] {
    let rejected = try {
      ignore(Archive::open(envelope(header)))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let bytes = envelope(b"\x01\x02\x80\x80\x00\x80\x80\x00\x00\x00")
  let rejected = try {
    ignore(Archive::open(bytes, limits=Limits::new(entries=1)))
    false
  } catch {
    Limit(resource="archive property records", ..) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(Archive::open(bytes).properties().length(), 2)
}

///|
test "archive property differences are visible even when member changes are empty" {
  let left = Archive::open(envelope(b"\x01\x02\x80\x80\x01a\x00\x00"))
  let right = Archive::open(envelope(b"\x01\x02\x80\x80\x01b\x00\x00"))
  let comparison = left.compare(right)
  assert_eq(comparison.changes(), [])
  assert_true(comparison.archive_properties_changed())
  assert_true(!comparison.identical())
  assert_true(
    comparison.to_json()
    is {
      "archive_properties_changed": True,
      "left_archive_properties": Array([{ "data_base64": String("YQ=="), .. }]),
      "right_archive_properties": Array([{ "data_base64": String("Yg=="), .. }]),
      ..
    },
  )
  assert_eq(@json.parse(comparison.to_json().stringify()), comparison.to_json())
  assert_true(left.compare(left).identical())
  assert_true(!left.compare(Archive::open(envelope(b""))).identical())
}
