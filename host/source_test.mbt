///|
async test "source readers match memory archives for all codec header graph and metadata fixtures" {
  let paths : Array[String] = [
    "corpus/copy-plain.7z", "corpus/lzma-solid.7z", "corpus/lzma2-solid.7z", "corpus/delta-solid.7z",
    "corpus/bcj-lzma2.7z", "corpus/arm64-lzma2.7z",
  ]
  for
    directory in [
      "bcj2", "deflate", "bzip2", "riscv", "external", "semantics", "lzma1", "ppmd",
      "branches", "producers", "encrypted",
    ] {
    for name in @fs.readdir("corpus/" + directory) {
      if name.has_suffix(".7z") {
        paths.push("corpus/" + directory + "/" + name)
      }
    }
  }
  for path in paths {
    let password = if path.contains("ppmd") {
      "moon7z-ppmd"
    } else if path.contains("/encrypted/") {
      "moon7z-密码-🔑"
    } else {
      "moon7z"
    }
    let memory = @host.open_file(path, password~)
    let opened = @host.open_seekable_file(path, password~)
    defer opened.close()
    let source = opened.archive
    assert_eq(source.entries(), memory.entries())
    assert_eq(source.properties(), memory.properties())
    assert_eq(source.metadata_streams(), memory.metadata_streams())
    assert_eq(source.file_properties(), memory.file_properties())
    assert_eq(source.is_encrypted(), memory.is_encrypted())
    let checked = source.verify()
    assert_eq(checked.bytes, memory.verify().bytes.to_uint64())
    let reader = source.reader()
    for item in memory.extract_all() {
      assert_eq(reader.read(item.entry.id), item)
      if item.entry.kind == File {
        assert_eq(
          reader.read_range(
            item.entry.id,
            offset=0,
            length=item.bytes.length().min(8),
          ),
          item.bytes[:item.bytes.length().min(8)].to_owned(),
        )
      }
    }
    let json = source.inventory_json()
    assert_eq(@json.parse(json.stringify()), json)
    assert_eq(source.inventory_json().stringify(), json.stringify())
  }
}

///|
async test "virtual archive above four GiB reads only header and selected folder with exact UInt64 offsets" {
  let start = @fs.read_file("corpus/source64/start.bin").binary()
  let tail = @fs.read_file("corpus/source64/tail.bin").binary()
  let expected = @fs.read_file("corpus/source/清单.json").binary()
  let calls : Array[(UInt64, Int32)] = []
  let source = @archive.SeekableInput::new(
    4294967328UL + tail.length().to_uint64(),
    (offset, length) => {
      calls.push((offset, length))
      if offset < 32UL && length.to_uint64() <= 32UL - offset {
        start[offset.to_int():offset.to_int() + length].to_owned()
      } else {
        assert_true(offset >= 4294967328UL)
        let index = (offset - 4294967328UL).to_int()
        tail[index:index + length].to_owned()
      }
    },
  )
  let archive = @archive.SourceArchive::open(source)
  assert_eq(archive.entries().length(), 65)
  assert_eq(calls.length(), 2)
  assert_true(calls[1].0 > 4294967296UL)
  assert_true(
    try {
      ignore(archive.verify(require_member_crcs=true))
      false
    } catch {
      @archive.MissingChecksum(id=0, ..) => true
      _ => false
    },
  )
  assert_eq(calls.length(), 2)
  let reader = archive.reader()
  assert_eq(reader.read(64).bytes, expected)
  assert_eq(calls[2], (4294967328UL, expected.length()))
  assert_eq(reader.read_range(64, offset=0, length=1), expected[:1].to_owned())
  assert_eq(calls.length(), 3)
  assert_eq(reader.read_many([64, 64])[1].bytes, expected)
  assert_eq(
    reader.read_ranges([@archive.RangeRequest::new(64, offset=0, length=3)])[0],
    expected[:3].to_owned(),
  )
  assert_eq(calls.length(), 3)
  let document = archive.inventory_json()
  assert_true(
    document is { "source_bytes": String(size), "contents_verified": False, .. } &&
    size == source.size.to_string(),
  )
  let seam = 4294967330UL
  let pieces = [
    @archive.SeekableInput::new(19UL, async fn(offset, length) {
      source.read_at(offset, length)
    }),
    @archive.SeekableInput::new(seam - 19UL, async fn(offset, length) {
      source.read_at(offset + 19UL, length)
    }),
    @archive.SeekableInput::new(source.size - seam, async fn(offset, length) {
      source.read_at(offset + seam, length)
    }),
  ]
  let composed = @archive.SourceArchive::open(
    @archive.SeekableInput::concat(pieces[:]),
  )
  assert_eq(composed.entries(), archive.entries())
  assert_eq(composed.reader().read(64).bytes, expected)
}

///|
async test "positioned volume files and empty composite seams preserve exact data" {
  for
    (id, encrypted) in [
      ("fixed", false),
      ("variable", false),
      ("encrypted", true),
    ] {
    let directory = "corpus/volumes/" + id
    let paths = @fs.readdir(directory, sort=true).map(name => {
      directory + "/" + name
    })
    let opened = @host.open_seekable_volumes(
      paths[:],
      password="moon7z-volumes",
    )
    defer opened.close()
    assert_eq(opened.archive.verify().bytes, 14229UL)
    assert_eq(opened.archive.is_encrypted(), encrypted)
    let old = @host.open_volume_files(paths[:], password="moon7z-volumes")
    let reader = opened.archive.reader()
    for item in old.archive.extract_all() {
      assert_eq(reader.read(item.entry.id), item)
    }
  }
  let pieces = [b"", b"a", b"", b"bc", b"\x00\xff", b""]
  let inputs = pieces.map(bytes => {
    @archive.SeekableInput::new(bytes.length().to_uint64(), (offset, length) => {
      bytes[offset.to_int():offset.to_int() + length].to_owned()
    })
  })
  let composite = @archive.SeekableInput::concat(inputs[:])
  inputs.clear()
  let expected = b"abc\x00\xff"
  for offset in 0..<=5 {
    for length in 0..<=(5 - offset) {
      assert_eq(
        composite.read_at(offset.to_uint64(), length),
        expected[offset:offset + length].to_owned(),
      )
    }
  }
}

///|
async test "live source policy cache recovery exact read contract and close lifetime" {
  let bytes = @fs.read_file("corpus/lzma2-solid.7z").binary()
  let calls : Array[(UInt64, Int32)] = []
  let source = @archive.SeekableInput::new(bytes.length().to_uint64(), (
    offset,
    length,
  ) => {
    calls.push((offset, length))
    bytes[offset.to_int():offset.to_int() + length].to_owned()
  })
  let archive = @archive.SourceArchive::open(source)
  assert_true(calls.all(call => call.0 != 32UL))
  let before = calls.length()
  let reader = archive.reader()
  let first = archive
    .entries()
    .filter(entry => entry.kind == File && entry.size > 0)[0]
  assert_true(
    try {
      ignore(reader.read(-1))
      false
    } catch {
      @archive.NoSuchEntry(..) => true
      _ => false
    },
  )
  assert_eq(calls.length(), before)
  let item = reader.read(first.id)
  assert_eq(reader.read(first.id), item)
  assert_eq(reader.stats().decode_attempts, 1)
  assert_eq(reader.stats().cache_hits, 1)
  assert_true(reader.stats().cached_bytes > 0)
  reader.clear_cache()
  assert_eq(reader.stats().cached_bytes, 0)
  assert_eq(reader.read(first.id), item)
  assert_true(
    try {
      ignore(@archive.SourceArchive::open(source, max_source_bytes=1UL))
      false
    } catch {
      @archive.SourceLimit(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(@archive.SourceArchive::open(source, max_output_bytes=1UL))
      false
    } catch {
      @archive.SourceLimit(..) => true
      _ => false
    },
  )
  let short = @archive.SeekableInput::new(32UL, (_, _) => b"short")
  assert_true(
    try {
      ignore(short.read_at(0UL, 32))
      false
    } catch {
      @archive.SourceRead(..) => true
      _ => false
    },
  )
  let opened = @host.open_seekable_file("corpus/lzma2-solid.7z")
  let live = opened.archive.reader()
  opened.close()
  opened.close()
  let closed = try {
    ignore(live.read(first.id))
    ""
  } catch {
    err => err.to_string()
  }
  assert_true(closed.contains("closed"))
  for password in [None, Some("wrong")] {
    assert_true(
      try {
        let failed = @host.open_seekable_file(
          "corpus/encrypted/v2605-header.7z",
          password?,
        )
        failed.close()
        false
      } catch {
        @archive.PasswordRequired | @archive.DecryptionFailed => true
        _ => false
      },
    )
  }
  let encrypted_file = @host.open_seekable_file(
    "corpus/encrypted/v2605-header.7z",
    password="moon7z-密码-🔑",
  )
  defer encrypted_file.close()
  assert_eq(encrypted_file.archive.verify().bytes, 4099UL)
}

///|
async test "source truncation failed I/O and file mutation recover without caching unchecked data" {
  let bytes = @fs.read_file("corpus/lzma2-solid.7z").binary()
  for size in [0, 1, 7, 31, 32, bytes.length() - 1] {
    let source = @archive.SeekableInput::new(size.to_uint64(), (offset, length) => {
      bytes[offset.to_int():offset.to_int() + length].to_owned()
    })
    assert_true(
      try {
        ignore(@archive.SourceArchive::open(source))
        false
      } catch {
        _ => true
      },
    )
  }
  let fail_next = [false]
  let source = @archive.SeekableInput::new(bytes.length().to_uint64(), (
    offset,
    length,
  ) => {
    if fail_next[0] {
      fail_next[0] = false
      fail("simulated transient I/O")
    }
    bytes[offset.to_int():offset.to_int() + length].to_owned()
  })
  let archive = @archive.SourceArchive::open(source)
  let id = archive
    .entries()
    .filter(entry => entry.kind == File && entry.size > 0)[0].id
  let reader = archive.reader()
  fail_next[0] = true
  let error = try {
    ignore(reader.read(id))
    ""
  } catch {
    err => err.to_string()
  }
  assert_true(error.contains("transient I/O"))
  assert_eq(reader.stats().cached_bytes, 0)
  assert_eq(reader.stats().decode_attempts, 1)
  let expected = @archive.Archive::open(bytes).reader().read(id)
  assert_eq(reader.read(id), expected)
  let snapshot = reader.stats()
  assert_true(
    try {
      ignore(reader.read_range(id, offset=-1, length=1))
      false
    } catch {
      @archive.InvalidRange(..) => true
      _ => false
    },
  )
  assert_eq(reader.stats(), snapshot)
  let too_long = @archive.SeekableInput::new(32UL, (_, _) => b"x".repeat(33))
  assert_true(
    try {
      ignore(too_long.read_at(0UL, 32))
      false
    } catch {
      @archive.SourceRead(..) => true
      _ => false
    },
  )
  let root = @fs.tmpdir(prefix="moon7z-source-change")
  defer @fs.rmdir(root, recursive=true)
  let path = root + "/changed.7z"
  @fs.write_file(path, bytes)
  let opened = @host.open_seekable_file(path)
  defer opened.close()
  @fs.write_file(path, b"x", append=true)
  let changed = try {
    ignore(opened.archive.reader().read(id))
    ""
  } catch {
    err => err.to_string()
  }
  assert_true(changed.contains("changed length"))
  opened.close()
  @fs.write_file(path, bytes)
  let recovered = @host.open_seekable_file(path)
  defer recovered.close()
  assert_eq(recovered.archive.reader().read(id), expected)
}
