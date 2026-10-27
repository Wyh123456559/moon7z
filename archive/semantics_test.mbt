///|
test "anti links reparse and special entries retain data while restoration refuses unsafe semantics" {
  let archive = @archive.Archive::open(semantics_mixed)
  let entries = archive.entries()
  assert_eq(entries.map(entry => entry.anti), [
    false, false, false, true, true, false,
  ])
  assert_eq(entries.map(entry => entry.semantics()), [
    Regular,
    SymbolicLink,
    Special,
    Regular,
    Regular,
    ReparsePoint,
  ])
  assert_eq(archive.extract_all()[0].bytes, manifest)
  assert_eq(archive.reader().read(1).bytes, b"manifest.json")
  assert_eq(entries[1].metadata.attributes, Some(0xa1ff8020U))
  assert_eq(archive.verify().bytes, manifest.length() + 13)
  assert_true(archive.audit().all_available_checks_passed())
  for id in [1, 2, 3, 4, 5] {
    assert_true(
      capture(() => archive.plan_selection([id]))
      is Err(@archive.UnsafePath(..)),
    )
  }
  assert_true(
    capture(() => archive.plan_contents()) is Err(@archive.UnsafePath(..)),
  )
  assert_eq(archive.plan_selection([0]).entries().map(entry => entry.id), [0])
  assert_eq(archive.plan_selection([]).entries(), [])
  assert_true(
    @json.parse(archive.inventory_json().stringify())
    is {
      "entries": Array(
        [
          _,
          { "semantics": String("symbolic_link"), "anti": False, .. },
          _,
          { "anti": True, .. },
          ..,
        ]
      ),
      ..
    },
  )
}

///|
test "opaque file properties preserve repeated UInt64 IDs and bytes through JSON and comparison" {
  let safe = @archive.Archive::open(semantics_safe)
  assert_eq(safe.entries()[0].metadata.start_position, None)
  assert_eq(safe.file_properties(), [])
  assert_eq(safe.plan_contents().entries().length(), 1)
  assert_eq(safe.extract_all()[0].bytes, manifest)
  assert_true(
    capture(() => {
      @archive.Archive::open(
        semantics_safe,
        limits=@archive.Limits::new(file_property_records=-1),
      )
    })
    is Err(@archive.Invalid(..)),
  )
  let archive = @archive.Archive::open(semantics_extended)
  let properties = archive.file_properties()
  assert_eq(properties.map(property => property.id), [
    128UL, 128UL, 0xffffffffffffffffUL,
  ])
  assert_eq(properties.map(property => property.data), [
    b"\x00\xffextension", b"", b"original",
  ])
  properties.clear()
  assert_eq(archive.file_properties().length(), 3)
  assert_eq(archive.extract_all()[0].bytes, manifest)
  assert_eq(archive.reader().read(0).bytes, manifest)
  assert_true(
    capture(() => archive.plan_selection([0])) is Err(@archive.UnsafePath(..)),
  )
  assert_eq(archive.plan_selection([]).entries(), [])
  assert_true(
    capture(() => archive.plan_selection([99])) is Err(@archive.NoSuchEntry(..)),
  )
  let diff = archive.compare(@archive.Archive::open(semantics_changed))
  assert_eq(diff.changes(), [])
  assert_true(diff.file_properties_changed())
  assert_true(!diff.identical())
  let json = archive.inventory_json()
  assert_eq(@json.parse(json.stringify()), json)
  assert_true(
    json
    is {
      "file_properties": Array(
        [_, _, { "id": String("18446744073709551615"), .. }]
      ),
      ..
    },
  )
  let positioned = @archive.Archive::open(semantics_position)
  assert_eq(positioned.entries()[0].metadata.start_position, Some(0UL))
  assert_eq(positioned.plan_contents().entries().length(), 1)
  assert_eq(safe.compare(positioned).changes()[0].kind, MetadataChanged)
  assert_eq(archive.inventory_json(), archive.inventory_json())
  assert_eq(
    archive.compare(archive).to_json(),
    archive.compare(archive).to_json(),
  )
  assert_true(
    capture(() => {
      @archive.Archive::open(
        semantics_extended,
        limits=@archive.Limits::new(file_property_records=1),
      )
    })
    is Err(@archive.Limit(..)),
  )
}
