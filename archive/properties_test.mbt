///|
test "independently unpacked archive metadata coexists with original member behavior" {
  let archive = @archive.Archive::open(property_archive)
  let base = @archive.Archive::open(copy_archive)
  let properties = archive.properties()
  assert_eq(properties.map(property => property.id), [128UL, 255UL, 128UL])
  assert_eq(properties.map(property => property.data), [
    b"\x00\xffA\n", b"", b"x",
  ])
  properties.clear()
  assert_eq(archive.properties().length(), 3)
  assert_eq(archive.entries(), base.entries())
  assert_eq(archive.extract_all(), base.extract_all())
  assert_eq(archive.verify(), base.verify())
  assert_eq(
    archive.reader().read_many([6, 3, 6]),
    base.reader().read_many([6, 3, 6]),
  )
  let difference = base.compare(archive)
  assert_true(difference.archive_properties_changed())
  assert_true(!difference.identical())
  assert_eq(difference.changes(), [])
  assert_eq(
    @json.parse(archive.inventory_json().stringify()),
    archive.inventory_json(),
  )
  let plan = archive.plan_contents()
  assert_eq(plan.entries(), base.plan_contents().entries())
}
