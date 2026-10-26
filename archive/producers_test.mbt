///|
fn producer_cases() -> Array[(String, Bytes)] {
  [
    ("v1900-copy", producer_v1900_copy),
    ("v1900-lzma-solid", producer_v1900_lzma_solid),
    ("v1900-lzma2-solid", producer_v1900_lzma2_solid),
    ("v1900-lzma2-separate", producer_v1900_lzma2_separate),
    ("v2301-copy", producer_v2301_copy),
    ("v2301-lzma-solid", producer_v2301_lzma_solid),
    ("v2301-lzma2-solid", producer_v2301_lzma2_solid),
    ("v2301-lzma2-separate", producer_v2301_lzma2_separate),
    ("v2409-copy", producer_v2409_copy),
    ("v2409-lzma-solid", producer_v2409_lzma_solid),
    ("v2409-lzma2-solid", producer_v2409_lzma2_solid),
    ("v2409-lzma2-separate", producer_v2409_lzma2_separate),
    ("v2501-copy", producer_v2501_copy),
    ("v2501-lzma-solid", producer_v2501_lzma_solid),
    ("v2501-lzma2-solid", producer_v2501_lzma2_solid),
    ("v2501-lzma2-separate", producer_v2501_lzma2_separate),
    ("v2605-copy", producer_v2605_copy),
    ("v2605-lzma-solid", producer_v2605_lzma_solid),
    ("v2605-lzma2-solid", producer_v2605_lzma2_solid),
    ("v2605-lzma2-separate", producer_v2605_lzma2_separate),
    ("libarchive", producer_libarchive),
  ]
}

///|
test "five official producers and libarchive preserve the real source tree" {
  let expected : Map[String, Bytes] = {
    "lzma-mbt/LICENSE": upstream_license,
    "lzma-mbt/README.md": upstream_readme,
    "lzma-mbt/moon.mod": upstream_module,
    "清单.json": manifest,
    "empty.txt": b"",
  }
  let cases = producer_cases()
  assert_eq(cases.length(), 21)
  for (name, bytes) in cases {
    assert_eq(bytes[6], b'\x00')
    assert_eq(bytes[7], if name == "libarchive" { b'\x03' } else { b'\x04' })
    let archive = @archive.Archive::open(bytes)
    let items = archive.extract_all()
    assert_eq(items.length(), 7)
    let seen : Set[String] = Set([])
    for item in items {
      assert_true(!seen.contains(item.entry.name))
      seen.add(item.entry.name)
      match item.entry.kind {
        File => assert_eq(item.bytes, expected[item.entry.name])
        Directory =>
          assert_true(["lzma-mbt", "空目录"].contains(item.entry.name))
      }
    }
    let checked = archive.verify()
    assert_eq(checked.files, 5)
    assert_eq(checked.bytes, 14550)
    assert_true(archive.audit().all_available_checks_passed())
    let entry = archive.entries().filter(entry => entry.name == "清单.json")[0]
    assert_eq(archive.reader().read(entry.id).bytes, manifest)
    assert_eq(
      @json.parse(archive.inventory_json().stringify()),
      archive.inventory_json(),
    )
    assert_eq(archive.extract_all(), items)
  }
}

///|
test "producer variants retain boundary and checksum failures with healthy recovery" {
  for (name, bytes) in producer_cases() {
    for length in [0, 7, 31, 32, bytes.length() - 1] {
      assert_true(
        capture(() => @archive.Archive::open(bytes[:length].to_owned()))
        is Err(_),
      )
    }
    assert_true(
      capture(() => {
        @archive.Archive::open(
          bytes,
          limits=@archive.Limits::new(output_bytes=14549),
        )
      })
      is Err(@archive.Limit(..)),
    )
    if name.has_suffix("-copy") {
      let changed = bytes.to_array()
      changed[32] = (changed[32].to_int() ^ 1).to_byte()
      let bad = @archive.Archive::open(Bytes::from_array(changed))
      assert_true(capture(() => bad.verify()) is Err(@archive.Checksum(..)))
    }
    assert_eq(@archive.Archive::open(bytes).verify().bytes, 14550)
  }
}
