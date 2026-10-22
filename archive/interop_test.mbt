///|
#warnings("-result_error_return")
fn[T] capture(
  f : () -> T raise @archive.ArchiveError,
) -> Result[T, @archive.ArchiveError] {
  Ok(f()) catch {
    err => Err(err)
  }
}

///|
fn assert_import(bytes : Bytes, blocks : Int32) -> Unit raise {
  let archive = @archive.Archive::open(bytes)
  let entries = archive.entries()
  assert_eq(entries.length(), 7)
  let expected : Map[String, Bytes] = {
    "lzma-mbt/LICENSE": upstream_license,
    "lzma-mbt/README.md": upstream_readme,
    "lzma-mbt/moon.mod": upstream_module,
    "清单.json": manifest,
    "empty.txt": b"",
  }
  let tree = archive.extract_all()
  let seen : Set[String] = Set([])
  for item in tree {
    assert_true(!seen.contains(item.entry.name))
    seen.add(item.entry.name)
    match item.entry.kind {
      File => {
        assert_eq(item.bytes, expected[item.entry.name])
        assert_eq(item.entry.size, item.bytes.length())
      }
      Directory =>
        assert_true(
          item.entry.name == "lzma-mbt" || item.entry.name == "空目录",
        )
    }
  }
  let report = archive.verify()
  assert_eq(report.files, 5)
  assert_eq(report.bytes, 14550)
  assert_eq(report.blocks, blocks)
  assert_eq(report.member_crcs_checked, 4)
  assert_eq(report.members_without_crc, 1)
  assert_eq(tree, archive.extract_all())
  entries.clear()
  assert_eq(archive.entries().length(), 7)
}

///|
test "Copy with plain header imports all original bytes" {
  assert_import(copy_archive, 4)
}

///|
test "LZMA with compressed header imports a solid archive" {
  assert_import(lzma_archive, 1)
}

///|
test "LZMA2 with compressed header imports a solid archive" {
  assert_import(lzma2_archive, 1)
}

///|
test "LZMA2 separate folders preserve the same file tree" {
  assert_import(separate_archive, 4)
}

///|
test "every truncated prefix is rejected without a panic" {
  for length in 0..<copy_archive.length() {
    let result = capture(() => {
      @archive.Archive::open(copy_archive[:length].to_owned())
    })
    assert_true(result is Err(_))
  }
}

///|
test "start header and next header corruption are rejected" {
  for offset in [8, 12, copy_archive.length() - 2] {
    let changed = copy_archive.to_array()
    changed[offset] = (changed[offset].to_int() ^ 1).to_byte()
    assert_true(
      capture(() => @archive.Archive::open(Bytes::from_array(changed)))
      is Err(_),
    )
  }
}

///|
test "corrupted payload fails verification and later imports still succeed" {
  let changed = copy_archive.to_array()
  changed[32] = (changed[32].to_int() ^ 1).to_byte()
  let damaged = @archive.Archive::open(Bytes::from_array(changed))
  assert_true(capture(() => damaged.verify()) is Err(@archive.Checksum(..)))
  assert_import(lzma2_archive, 1)
}

///|
test "all configured limits are enforced before decoding" {
  for
    limits in [
      @archive.Limits::new(input_bytes=1),
      @archive.Limits::new(header_bytes=1),
      @archive.Limits::new(output_bytes=1),
      @archive.Limits::new(dictionary_bytes=1),
      @archive.Limits::new(entries=1),
    ] {
    assert_true(
      capture(() => @archive.Archive::open(lzma2_archive, limits~))
      is Err(@archive.Limit(..)),
    )
  }
  assert_true(
    capture(() => {
      @archive.Archive::open(
        copy_archive,
        limits=@archive.Limits::new(input_bytes=-1),
      )
    })
    is Err(@archive.Invalid(..)),
  )
  let exact = @archive.Limits::new(
    input_bytes=lzma2_archive.length(),
    output_bytes=14550,
  )
  assert_eq(
    @archive.Archive::open(lzma2_archive, limits=exact).verify().bytes,
    14550,
  )
}

///|
test "trailing data and self extracting prefixes are refused" {
  assert_true(
    capture(() => @archive.Archive::open(copy_archive + b"trailing")) is Err(_),
  )
  assert_true(
    capture(() => @archive.Archive::open(b"MZ" + copy_archive)) is Err(_),
  )
}
