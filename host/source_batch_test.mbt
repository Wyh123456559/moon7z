///|
async test "source batches preserve order duplicates intervals and one decode with cache disabled" {
  let opened = @host.open_seekable_file("corpus/lzma2-solid.7z")
  defer opened.close()
  let archive = opened.archive
  let reader = archive.reader(cache_bytes=0)
  let ids = [6, 3, 6, 2, 0]
  let memory = @host.open_file("corpus/lzma2-solid.7z").reader(cache_bytes=0)
  assert_eq(reader.read_many(ids[:]), memory.read_many(ids[:]))
  assert_eq(reader.stats().decode_attempts, 1)
  assert_eq(reader.stats().cached_bytes, 0)
  let requests = [
    @archive.RangeRequest::new(6, offset=0, length=4),
    @archive.RangeRequest::new(3, offset=1, length=7),
    @archive.RangeRequest::new(6, offset=2, length=3),
    @archive.RangeRequest::new(6, offset=52, length=0),
  ]
  assert_eq(reader.read_ranges(requests[:]), memory.read_ranges(requests[:]))
  assert_eq(reader.stats().decode_attempts, 2)
  assert_eq(reader.read_many([]), [])
  assert_eq(reader.read_ranges([]), [])
  assert_eq(reader.stats().decode_attempts, 2)
}

///|
async test "source batch preflight count and copy budgets preserve I/O and cached data" {
  let bytes = @fs.read_file("corpus/lzma2-solid.7z").binary()
  let calls : Array[UInt64] = []
  let source = @archive.SeekableInput::new(bytes.length().to_uint64(), (
    offset,
    length,
  ) => {
    calls.push(offset)
    bytes[offset.to_int():offset.to_int() + length].to_owned()
  })
  let archive = @archive.SourceArchive::open(
    source,
    limits=@archive.Limits::new(output_bytes=15000, entries=8),
  )
  let reader = archive.reader()
  ignore(reader.read(6))
  let previous = reader.stats()
  let count = calls.length()
  for ids in [[6, -1], [3, 3], Array::make(9, 6)] {
    assert_true(
      try {
        ignore(reader.read_many(ids[:]))
        false
      } catch {
        _ => true
      },
    )
  }
  for
    requests in [
      [
        @archive.RangeRequest::new(6, offset=0, length=1),
        @archive.RangeRequest::new(6, offset=53, length=0),
      ],
      [@archive.RangeRequest::new(0, offset=0, length=0)],
      [
        @archive.RangeRequest::new(3, offset=0, length=11000),
        @archive.RangeRequest::new(3, offset=0, length=11000),
      ],
      Array::make(9, @archive.RangeRequest::new(6, offset=0, length=0)),
    ] {
    assert_true(
      try {
        ignore(reader.read_ranges(requests[:]))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_eq(calls.length(), count)
  assert_eq(reader.stats(), previous)
  assert_eq(
    reader.read_many([6, 6])[0].bytes,
    @fs.read_file("corpus/source/清单.json").binary(),
  )
}

///|
async test "source selected exports refuse replace and roll back late failures" {
  let root = @fs.tmpdir(prefix="moon7z-source-selected")
  defer @fs.rmdir(root, recursive=true)
  let bytes = @fs.read_file("corpus/copy-plain.7z").binary()
  let changed = bytes.to_array()
  changed[32] = (changed[32].to_int() ^ 1).to_byte()
  let damaged = @archive.SourceArchive::open(
    memory_input(Bytes::from_array(changed)),
  )
  let healthy = @archive.SourceArchive::open(memory_input(bytes))
  let result = @host.export_source_selected(
    damaged,
    [6],
    parent=root,
    name="manifest",
  )
  assert_eq(result.entries.map(entry => entry.id), [6])
  assert_eq(
    @fs.read_file(result.directory + "/清单.json").binary(),
    @fs.read_file("corpus/source/清单.json").binary(),
  )
  for
    (name, ids) in [
      ("bad", [6, 3]),
      ("duplicate", [6, 6]),
      ("invalid", [-1]),
      ("manifest", [6]),
    ] {
    assert_true(
      try {
        ignore(
          @host.export_source_selected(damaged, ids[:], parent=root, name~),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  assert_eq(@fs.readdir(root, include_hidden=true), ["manifest"])
  let directory = @host.export_source_selected(
    healthy,
    [0],
    parent=root,
    name="directory",
  )
  assert_eq(@fs.readdir(directory.directory + "/lzma-mbt"), [])
  let empty = @host.export_source_selected(
    healthy,
    [],
    parent=root,
    name="empty",
  )
  assert_eq(empty.entries, [])
  assert_eq(@fs.readdir(empty.directory), [])
  let recovered = @host.export_source_selected(
    healthy,
    [6, 3],
    parent=root,
    name="recovered",
  )
  assert_eq(recovered.entries.map(entry => entry.id), [6, 3])
}

///|
async test "batch decode failures clear unchecked cache and source retry succeeds" {
  let bytes = @fs.read_file("corpus/lzma2-solid.7z").binary()
  let mut broken = false
  let source = @archive.SeekableInput::new(bytes.length().to_uint64(), (
    offset,
    length,
  ) => {
    if broken && offset == 32UL {
      raise AuditReadFailure
    }
    bytes[offset.to_int():offset.to_int() + length].to_owned()
  })
  let archive = @archive.SourceArchive::open(source)
  let reader = archive.reader()
  broken = true
  assert_true(
    try {
      ignore(
        reader.read_ranges([@archive.RangeRequest::new(6, offset=0, length=0)]),
      )
      false
    } catch {
      AuditReadFailure => true
      _ => false
    },
  )
  assert_eq(reader.stats().cached_bytes, 0)
  broken = false
  assert_eq(reader.read_many([6, 6]).length(), 2)
  assert_true(reader.stats().cached_bytes > 0)
}

///|
async test "batch and selected exports use volumes and SFX without joining input" {
  let root = @fs.tmpdir(prefix="moon7z-source-batch-adapters")
  defer @fs.rmdir(root, recursive=true)
  let paths = Array::makei(6, i => {
    "corpus/volumes/variable/package.7z.00" + (i + 1).to_string()
  })
  let volumes = @host.open_seekable_volumes(paths[:])
  defer volumes.close()
  let expected = @fs.read_file("corpus/source/清单.json").binary()
  let item = volumes.archive
    .entries()
    .filter(entry => entry.name == "清单.json")[0]
  assert_eq(
    volumes.archive.reader(cache_bytes=0).read_many([item.id, item.id])[1].bytes,
    expected,
  )
  ignore(
    @host.export_source_selected(
      volumes.archive,
      [item.id],
      parent=root,
      name="volume",
    ),
  )
  let text = @fs.read_file("corpus/sfx/gui.base64").text()
  let sfx = @archive.SourceEmbeddedArchive::open(
    memory_input(@base64.decode(text.split("\n").join(""))),
  )
  let selected = sfx.archive
    .entries()
    .filter(entry => entry.name == "清单.json")[0]
  assert_eq(
    sfx.archive.reader(cache_bytes=0).read_many([selected.id])[0].bytes,
    expected,
  )
  ignore(
    @host.export_source_selected(
      sfx.archive,
      [selected.id],
      parent=root,
      name="sfx",
    ),
  )
  assert_eq(
    @fs.read_file(root + "/volume/清单.json").binary(),
    @fs.read_file(root + "/sfx/清单.json").binary(),
  )
}
