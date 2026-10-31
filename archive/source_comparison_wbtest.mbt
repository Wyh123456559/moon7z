///|
test "source comparison JSON preserves UInt64 totals and opaque metadata without narrowing" {
  let verification : SourceVerification = {
    files: 1,
    bytes: 0xffffffffffffffffUL,
    blocks: 1,
    member_crcs_checked: 0,
    members_without_crc: 1,
  }
  let result : SourceComparison = {
    differences: [],
    left_report: verification,
    right_report: verification,
    before_properties: [],
    after_properties: [],
    before_streams: [b"\x00\xff"],
    after_streams: [b"\x00\xff"],
    before_file_properties: [{ id: 0xffffffffffffffffUL, data: b"\x00\xff", }],
    after_file_properties: [{ id: 0xffffffffffffffffUL, data: b"changed", }],
  }
  assert_true(!result.identical())
  assert_true(result.file_properties_changed())
  assert_true(!result.archive_properties_changed())
  assert_true(!result.metadata_streams_changed())
  let json = result.to_json()
  assert_eq(@json.parse(json.stringify()), json)
  assert_true(
    json
    is {
      "left_verification": { "bytes": String("18446744073709551615"), .. },
      ..
    },
  )
  assert_eq(result.to_json().stringify(), json.stringify())
}
