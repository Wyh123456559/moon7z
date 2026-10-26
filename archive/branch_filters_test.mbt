///|
fn assert_branch_archive(bytes : Bytes) -> Unit raise {
  let archive = @archive.Archive::open(bytes)
  let items = archive.extract_all()
  assert_eq(items.length(), 2)
  assert_eq(items[0].entry.name, "a-head.bin")
  assert_eq(items[1].entry.name, "b-tail.bin")
  assert_eq(items[0].bytes, branch_head)
  assert_eq(items[1].bytes, branch_tail)
  let report = archive.verify(require_member_crcs=true)
  assert_eq(report.bytes, 65539)
  assert_eq(report.member_crcs_checked, 2)
  assert_eq(report.blocks, 1)
  let reader = archive.reader()
  assert_eq(reader.read_many([1, 0, 1]), [items[1], items[0], items[1]])
  assert_eq(reader.stats().decode_attempts, 1)
  assert_eq(reader.read_range(1, offset=65533, length=3), b"\xaa\xbb\xcc")
  assert_eq(
    reader.read_ranges([
      @archive.RangeRequest::new(0, offset=1, length=2),
      @archive.RangeRequest::new(1, offset=0, length=17),
    ]),
    [branch_head[1:].to_owned(), branch_tail[:17].to_owned()],
  )
  assert_true(archive.audit().all_available_checks_passed())
  assert_eq(archive.extract_all(), items)
}

///|
test "five classic branch methods decode Copy and LZMA2 across solid members" {
  let original = branch_head + branch_tail
  for
    (copy, lzma2) in [
      (branch_arm_copy, branch_arm_lzma2),
      (branch_thumb_copy, branch_thumb_lzma2),
      (branch_ppc_copy, branch_ppc_lzma2),
      (branch_ia64_copy, branch_ia64_lzma2),
      (branch_sparc_copy, branch_sparc_lzma2),
    ] {
    assert_branch_archive(copy)
    assert_branch_archive(lzma2)
    // Plain Copy payload must actually differ: an inert filter is not evidence.
    assert_true(copy[32:32 + 65539].to_owned() != original)
    assert_true(
      @archive.Archive::open(copy)
      .compare(@archive.Archive::open(lzma2))
      .identical(),
    )
  }
}

///|
test "Swap2 and Swap4 reconstruct whole words across the member boundary" {
  for bytes in [branch_swap2_copy, branch_swap4_copy] {
    assert_branch_archive(bytes)
  }
}

///|
test "new filter paths retain limits CRC failure truncation and subsequent recovery" {
  for
    bytes in [
      branch_arm_copy, branch_thumb_copy, branch_ppc_copy, branch_ia64_copy, branch_sparc_copy,
      branch_swap2_copy, branch_swap4_copy,
    ] {
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
          limits=@archive.Limits::new(output_bytes=65538),
        )
      })
      is Err(@archive.Limit(..)),
    )
    let corrupt = bytes.to_array()
    corrupt[32] = (corrupt[32].to_int() ^ 1).to_byte()
    let bad = @archive.Archive::open(Bytes::from_array(corrupt))
    assert_true(capture(() => bad.verify()) is Err(@archive.Checksum(..)))
    assert_true(
      capture(() => bad.reader().read(1)) is Err(@archive.Checksum(..)),
    )
    assert_branch_archive(bytes)
  }
}
