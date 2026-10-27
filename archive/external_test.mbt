///|
test "external metadata preserves names FILETIMEs attributes opaque data and encoded header placement" {
  let base = @archive.Archive::open(external_metadata)
  let inline = @archive.Archive::open(external_inline)
  for
    bytes in [
      external_metadata, external_encoded_first, external_encoded_pieces,
    ] {
    let archive = @archive.Archive::open(bytes)
    assert_eq(archive.entries(), inline.entries())
    assert_eq(archive.entries()[0].name, "清单.json")
    assert_eq(archive.entries()[0].metadata.created, Some(133876800000000000UL))
    assert_eq(
      archive.entries()[0].metadata.accessed,
      Some(133876800000000001UL),
    )
    assert_eq(
      archive.entries()[0].metadata.modified,
      Some(133876800000000002UL),
    )
    assert_eq(archive.entries()[0].metadata.attributes, Some(32U))
    assert_eq(archive.extract_all()[0].bytes, manifest)
    assert_eq(archive.verify().bytes, manifest.length())
    assert_eq(archive.metadata_streams().length(), 7)
    assert_eq(archive.metadata_streams()[6], b"\x00\xffopaque")
    let detached = archive.metadata_streams()
    detached.clear()
    assert_eq(archive.metadata_streams().length(), 7)
    assert_true(archive.compare(base).identical())
    assert_eq(
      @json.parse(archive.inventory_json().stringify()),
      archive.inventory_json(),
    )
  }
  let changed = base.compare(@archive.Archive::open(external_changed))
  assert_eq(changed.changes(), [])
  assert_true(changed.metadata_streams_changed())
  assert_true(!changed.identical())
  let placement = base.compare(inline)
  assert_eq(placement.changes(), [])
  assert_true(placement.metadata_streams_changed())
  assert_true(!placement.identical())
  let damaged = external_metadata.to_array()
  let mut offset = 0UL
  let mut header_size = 0UL
  for i in 0..<8 {
    offset = offset | (damaged[12 + i].to_uint64() << (i * 8))
    header_size = header_size | (damaged[20 + i].to_uint64() << (i * 8))
  }
  let last = 32 + offset.to_int() - 1
  damaged[last] = (damaged[last].to_int() ^ 1).to_byte()
  assert_true(
    capture(() => @archive.Archive::open(Bytes::from_array(damaged)))
    is Err(@archive.Checksum(..)),
  )
  assert_true(
    capture(() => {
      @archive.Archive::open(
        external_metadata,
        limits=@archive.Limits::new(header_bytes=header_size.to_int()),
      )
    })
    is Err(@archive.Limit(..)),
  )
  assert_eq(
    @archive.Archive::open(external_metadata).verify().bytes,
    manifest.length(),
  )
}
