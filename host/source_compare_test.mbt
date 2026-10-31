///|
async test "source comparison ignores repacking preserves differences metadata and deterministic JSON" {
  let left = @host.open_seekable_file("corpus/copy-plain.7z")
  defer left.close()
  for
    path in [
      "corpus/lzma-solid.7z", "corpus/lzma2-solid.7z", "corpus/lzma2-separate.7z",
    ] {
    let right = @host.open_seekable_file(path)
    defer right.close()
    let report = left.archive.compare(right.archive)
    assert_true(report.identical())
    assert_eq(report.changes(), [])
    assert_eq(@json.parse(report.to_json().stringify()), report.to_json())
    assert_eq(
      report.to_json().stringify(),
      left.archive.compare(right.archive).to_json().stringify(),
    )
    assert_true(
      report.to_json()
      is { "left_verification": { "bytes": String("14550"), .. }, .. },
    )
  }
  let before = @host.open_seekable_file("corpus/binary.7z")
  defer before.close()
  let after = @host.open_seekable_file("corpus/arm64-lzma2.7z")
  defer after.close()
  let memory = @host.open_file("corpus/binary.7z").compare(
    @host.open_file("corpus/arm64-lzma2.7z"),
  )
  let report = before.archive.compare(after.archive)
  assert_eq(report.changes(), memory.changes())
  let copy = report.changes()
  copy.clear()
  assert_eq(report.changes().length(), 2)
}

///|
async test "source comparison verifies removed data and propagates transient I/O without partial results" {
  let original = @fs.read_file("corpus/binary.7z").binary()
  let changed = original.to_array()
  changed[32] = (changed[32].to_int() ^ 1).to_byte()
  let damaged = @archive.SourceArchive::open(
    memory_input(Bytes::from_array(changed)),
  )
  let other = @host.open_seekable_file("corpus/arm64-lzma2.7z")
  defer other.close()
  for (left, right) in [(damaged, other.archive), (other.archive, damaged)] {
    assert_true(
      try {
        ignore(left.compare(right))
        false
      } catch {
        @archive.Checksum(..) => true
        _ => false
      },
    )
  }
  let mut broken = false
  let source = @archive.SeekableInput::new(original.length().to_uint64(), (
    offset,
    length,
  ) => {
    if broken && offset == 32UL {
      raise AuditReadFailure
    }
    original[offset.to_int():offset.to_int() + length].to_owned()
  })
  let stable = @archive.SourceArchive::open(source)
  broken = true
  assert_true(
    try {
      ignore(stable.compare(other.archive))
      false
    } catch {
      AuditReadFailure => true
      _ => false
    },
  )
  broken = false
  assert_true(!stable.compare(other.archive).identical())
}

///|
async test "source comparison retains external metadata opaque properties and refuses strict missing CRCs" {
  let ordinary = @host.open_seekable_file("corpus/copy-plain.7z")
  defer ordinary.close()
  let properties = @host.open_seekable_file("corpus/properties/properties.7z")
  defer properties.close()
  let report = ordinary.archive.compare(properties.archive)
  assert_true(report.archive_properties_changed())
  assert_true(!report.identical())
  assert_true(
    try {
      ignore(
        ordinary.archive.compare(ordinary.archive, require_member_crcs=true),
      )
      false
    } catch {
      @archive.MissingChecksum(..) => true
      _ => false
    },
  )
  for name in @fs.readdir("corpus/external") {
    if name.has_suffix(".7z") {
      let file = @host.open_seekable_file("corpus/external/" + name)
      defer file.close()
      assert_true(file.archive.compare(file.archive).identical())
    }
  }
}

///|
async test "volumes and SFX compare decoded archives while explicitly excluding envelope bytes" {
  let paths = Array::makei(6, i => {
    "corpus/volumes/variable/package.7z.00" + (i + 1).to_string()
  })
  let volumes = @host.open_seekable_volumes(paths[:])
  defer volumes.close()
  let text = @fs.read_file("corpus/sfx/gui.base64").text()
  let bytes = @base64.decode(text.split("\n").join(""))
  let sfx = @archive.SourceEmbeddedArchive::open(memory_input(bytes))
  let compared = volumes.archive.compare(sfx.archive)
  let memory_left = @host.open_volume_files(paths[:])
  let memory_right = @archive.EmbeddedArchive::open(bytes)
  assert_eq(
    compared.changes(),
    memory_left.archive.compare(memory_right.archive).changes(),
  )
  let payload = @fs.read_file("corpus/copy-plain.7z").binary()
  let first = @archive.SourceEmbeddedArchive::open(
    memory_input(b"stub A" + payload + b"tail A"),
  )
  let second = @archive.SourceEmbeddedArchive::open(
    memory_input(b"longer stub B" + payload + b"tail B"),
  )
  assert_true(first.archive.compare(second.archive).identical())
}

///|
async test "comparison total output may exceed one decoded folder budget" {
  let opened = @host.open_seekable_file(
    "corpus/copy-plain.7z",
    limits=@archive.Limits::new(output_bytes=12000),
  )
  defer opened.close()
  let report = opened.archive.compare(opened.archive)
  assert_true(report.identical())
  assert_true(
    report.to_json()
    is { "left_verification": { "bytes": String("14550"), .. }, .. },
  )
}
