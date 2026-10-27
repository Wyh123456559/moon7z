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
fn matrix_u32(bytes : Bytes, at : Int32) -> Int32 {
  bytes[at].to_int() |
  (bytes[at + 1].to_int() << 8) |
  (bytes[at + 2].to_int() << 16) |
  (bytes[at + 3].to_int() << 24)
}

///|
test "all 225 independent LZMA1 lc lp pb archives decode complete package bytes" {
  let lzma_matrix = @base64.decode(lzma_matrix_text.split("\n").join(""))
  let expected : Map[String, Bytes] = {
    "README.md": upstream_readme,
    "LICENSE": upstream_license,
    "清单.json": manifest,
  }
  let mut index = 0
  assert_eq(lzma_matrix[:5], b"M7L1\x01"[:])
  assert_eq(matrix_u32(lzma_matrix, 5), 225)
  let mut offset = 9
  for _ in 0..<225 {
    assert_eq(lzma_matrix[offset].to_int(), index % 9)
    assert_eq(lzma_matrix[offset + 1].to_int(), index / 9 % 5)
    assert_eq(lzma_matrix[offset + 2].to_int(), index / 45)
    let size = matrix_u32(lzma_matrix, offset + 3)
    offset += 7
    let archive = @archive.Archive::open(
      lzma_matrix[offset:offset + size].to_owned(),
    )
    let items = archive.extract_all()
    assert_eq(items.length(), 3)
    for item in items {
      assert_eq(item.bytes, expected[item.entry.name])
    }
    offset += size
    index += 1
  }
  assert_eq(offset, lzma_matrix.length())
  assert_eq(index, 225)
}

///|
test "full literal contexts have independent model budgets and recover after failed reads" {
  let half = FixedArray::make(65536, b'\x00')
  let mut seed = 0x12345678U
  for i in 0..<65536 {
    seed = seed * 1664525U + 1013904223U
    half[i] = (seed >> 24).to_byte()
  }
  let first = Bytes::makei(65536, i => half[i])
  assert_eq(
    @archive.Archive::open(@base64.decode(history_text.split("\n").join(""))).extract_all()[0].bytes,
    first + first + b"end",
  )
  assert_true(
    @archive.Archive::open(lzma_eos)
    .compare(@archive.Archive::open(lzma_full))
    .identical(),
  )
  let required = (1846 + (0x300 << 12)) * 4
  assert_true(
    capture(() => {
      @archive.Archive::open(
        lzma_full,
        limits=@archive.Limits::new(lzma_probability_bytes=required - 1),
      )
    })
    is Err(@archive.Limit(resource="LZMA1 probability bytes", ..)),
  )
  let archive = @archive.Archive::open(
    lzma_full,
    limits=@archive.Limits::new(lzma_probability_bytes=required),
  )
  assert_eq(archive.verify().bytes, 14229)
  let reader = archive.reader()
  assert_true(
    capture(() => reader.read_range(0, offset=-1, length=1))
    is Err(@archive.InvalidRange(..)),
  )
  assert_eq(reader.stats().decode_attempts, 0)
  assert_eq(reader.read(0).bytes.length(), archive.entries()[0].size)
  assert_eq(
    reader.read_range(0, offset=0, length=1),
    reader.read(0).bytes[:1].to_owned(),
  )
  assert_true(archive.compare(@archive.Archive::open(lzma_full)).identical())
  assert_true(
    capture(() => {
      @archive.Archive::open(
        lzma_full,
        limits=@archive.Limits::new(lzma_probability_bytes=-1),
      )
    })
    is Err(@archive.Invalid(..)),
  )
}
