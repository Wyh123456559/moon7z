///|
fn memory_input(bytes : Bytes) -> @archive.SeekableInput {
  @archive.SeekableInput::new(bytes.length().to_uint64(), (offset, length) => {
    bytes[offset.to_int():offset.to_int() + length].to_owned()
  })
}

///|
async test "source SFX tiny read budgets password failures and transient I/O recover" {
  let empty = b"7z\xbc\xaf\x27\x1c\x00\x04\x8d\x9b\xd5\x0f" + b"\x00".repeat(20)
  let bytes = b"prefix" + empty + b"\x00\xfftail"
  let calls : Array[Int32] = []
  let source = @archive.SeekableInput::new(bytes.length().to_uint64(), (
    offset,
    length,
  ) => {
    calls.push(length)
    bytes[offset.to_int():offset.to_int() + length].to_owned()
  })
  let imported = @archive.SourceEmbeddedArchive::open(
    source,
    limits=@archive.Limits::new(input_bytes=32),
  )
  assert_eq(imported.offset, 6UL)
  assert_eq(imported.archive.verify().bytes, 0UL)
  assert_true(calls.all(length => length <= 32))
  let count = calls.length()
  assert_true(
    try {
      ignore(@archive.SourceEmbeddedArchive::open(source, search_bytes=0UL))
      false
    } catch {
      @archive.SourceSignatureNotFound(searched_bytes=0UL) => true
      _ => false
    },
  )
  assert_eq(calls.length(), count)
  for offset in [bytes.length().to_uint64(), 0xffffffffffffffffUL] {
    assert_true(
      try {
        ignore(@archive.SourceEmbeddedArchive::open_at(source, offset))
        false
      } catch {
        @archive.SourceRead(..) => true
        _ => false
      },
    )
  }
  assert_true(
    try {
      ignore(
        @archive.SourceEmbeddedArchive::open(
          source,
          limits=@archive.Limits::new(input_bytes=31),
        ),
      )
      false
    } catch {
      @archive.Limit(..) => true
      _ => false
    },
  )
  let encrypted = @fs.read_file("corpus/encrypted/v2605-header.7z").binary()
  let mixed = memory_input(b"MZ" + encrypted + empty)
  assert_true(
    try {
      ignore(@archive.SourceEmbeddedArchive::open(mixed))
      false
    } catch {
      @archive.PasswordRequired => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(@archive.SourceEmbeddedArchive::open(mixed, password="wrong"))
      false
    } catch {
      @archive.DecryptionFailed => true
      _ => false
    },
  )
  let recovered = @archive.SourceEmbeddedArchive::open(
    mixed,
    password="moon7z-密码-🔑",
  )
  assert_eq(recovered.archive.verify().bytes, 4099UL)
  assert_eq(recovered.suffix.read_at(0UL, 32), empty)
  let fail_next = [true]
  let flaky = @archive.SeekableInput::new(bytes.length().to_uint64(), (
    offset,
    length,
  ) => {
    if fail_next[0] {
      fail_next[0] = false
      fail("transient scan I/O")
    }
    bytes[offset.to_int():offset.to_int() + length].to_owned()
  })
  let message = try {
    ignore(@archive.SourceEmbeddedArchive::open(flaky))
    ""
  } catch {
    err => err.to_string()
  }
  assert_true(message.contains("transient scan I/O"))
  assert_eq(
    @archive.SourceEmbeddedArchive::open(flaky).archive.verify().bytes,
    0UL,
  )
}

///|
async test "split SFX header and archive seams retain exact envelope with close lifetime" {
  let text = @fs.read_file("corpus/sfx/gui.base64").text()
  let bytes = @base64.decode(text.split("\n").join("")) + b"\x00\xfffooter"
  let root = @fs.tmpdir(prefix="moon7z-source-sfx-parts")
  defer @fs.rmdir(root, recursive=true)
  let boundaries = [0, 35331, 35349, bytes.length() - 3, bytes.length()]
  let paths : Array[String] = []
  for i in 0..<4 {
    let path = root + "/bundle.7z.00" + (i + 1).to_string()
    @fs.write_file(path, bytes[boundaries[i]:boundaries[i + 1]].to_owned())
    paths.push(path)
  }
  let opened = @host.open_seekable_sfx_volumes(paths[:])
  defer opened.close()
  assert_eq(opened.embedded.offset, 35328UL)
  assert_eq(opened.embedded.archive.verify().bytes, 14229UL)
  let restored = @archive.SeekableInput::concat([
    opened.embedded.prefix,
    opened.embedded.payload,
    opened.embedded.suffix,
  ])
  assert_eq(restored.read_at(0UL, bytes.length()), bytes)
  opened.close()
  opened.close()
  let closed = try {
    ignore(opened.embedded.prefix.read_at(0UL, 1))
    ""
  } catch {
    err => err.to_string()
  }
  assert_true(closed.contains("closed"))
  let missing = try {
    ignore(@host.open_seekable_sfx_volumes([paths[0], paths[2]]))
    ""
  } catch {
    err => err.to_string()
  }
  assert_true(missing.contains("expected bundle.7z.002"))
  let known = @host.open_seekable_sfx_volumes(paths[:], offset=35328UL)
  defer known.close()
  assert_eq(known.embedded.archive.verify().bytes, 14229UL)
}

///|
async test "real SDK source SFX envelopes preserve bytes and share verified import workflows" {
  for
    (id, offset) in [("gui", 35328), ("console", 34816), ("installer", 129082)] {
    let text = @fs.read_file("corpus/sfx/" + id + ".base64").text()
    let bytes = @base64.decode(text.split("\n").join("")) + b"\x00\xfffooter"
    let imported = @archive.SourceEmbeddedArchive::open(memory_input(bytes))
    let ordinary = @archive.EmbeddedArchive::open(bytes)
    assert_eq(imported.offset, offset.to_uint64())
    assert_eq(imported.archive.entries(), ordinary.archive.entries())
    assert_eq(imported.archive.verify().bytes, 14229UL)
    assert_eq(imported.prefix.read_at(0UL, offset), ordinary.prefix)
    assert_eq(
      imported.payload.read_at(0UL, ordinary.payload.length()),
      ordinary.payload,
    )
    assert_eq(imported.suffix.read_at(0UL, 8), ordinary.suffix)
    let restored = @archive.SeekableInput::concat([
      imported.prefix,
      imported.payload,
      imported.suffix,
    ])
    assert_eq(restored.read_at(0UL, bytes.length()), bytes)
    let reader = imported.archive.reader()
    for item in ordinary.archive.extract_all() {
      assert_eq(reader.read(item.entry.id), item)
    }
    let json = imported.inventory_json()
    assert_eq(@json.parse(json.stringify()), json)
    assert_eq(imported.inventory_json().stringify(), json.stringify())
    assert_true(
      json
      is {
        "envelope_verified": False,
        "envelope_bytes_included": False,
        "suffix_bytes": String("8"),
        ..
      },
    )
  }
}

///|
async test "source SFX scanning crosses windows and never skips a credible broken header" {
  let payload = @fs.read_file("corpus/lzma2-solid.7z").binary()
  for offset in [0, 1, 65504, 65505, 65506, 1048576] {
    let input = memory_input(b"\x00".repeat(offset) + payload)
    assert_true(
      try {
        ignore(
          @archive.SourceEmbeddedArchive::open(
            input,
            search_bytes=offset.to_uint64(),
          ),
        )
        false
      } catch {
        @archive.SourceSignatureNotFound(..) => true
        _ => false
      },
    )
    let imported = @archive.SourceEmbeddedArchive::open(
      input,
      search_bytes=(offset + 1).to_uint64(),
    )
    assert_eq(imported.offset, offset.to_uint64())
    assert_eq(imported.archive.verify().bytes, 14550UL)
  }
  let bad_crc = payload[:32].to_owned().to_array()
  bad_crc[8] = bad_crc[8] ^ b'\x01'
  let decoy = Bytes::from_array(bad_crc) + payload
  assert_eq(
    @archive.SourceEmbeddedArchive::open(memory_input(decoy)).offset,
    32UL,
  )
  let broken = payload.to_array()
  broken[broken.length() - 1] = broken[broken.length() - 1] ^ b'\x01'
  let both = memory_input(Bytes::from_array(broken) + payload)
  assert_true(
    try {
      ignore(@archive.SourceEmbeddedArchive::open(both))
      false
    } catch {
      @archive.Checksum(..) => true
      _ => false
    },
  )
  assert_eq(
    @archive.SourceEmbeddedArchive::open_at(both, payload.length().to_uint64()).archive.verify().bytes,
    14550UL,
  )
  let future = payload.to_array()
  future[6] = b'\x01'
  assert_true(
    try {
      ignore(
        @archive.SourceEmbeddedArchive::open(
          memory_input(Bytes::from_array(future) + payload),
        ),
      )
      false
    } catch {
      @archive.Unsupported(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(
        @archive.SourceEmbeddedArchive::open(
          memory_input(payload[:payload.length() - 1].to_owned()),
        ),
      )
      false
    } catch {
      @archive.SourceRead(..) => true
      _ => false
    },
  )
}

///|
async test "known source SFX offsets above four GiB preserve opaque views and avoid prefix scanning" {
  let payload = @fs.read_file("corpus/lzma2-solid.7z").binary()
  let at = 0x100000007UL
  let suffix = b"\x00\xfftrailer"
  let calls : Array[(UInt64, Int32)] = []
  let source = @archive.SeekableInput::new(
    at + payload.length().to_uint64() + suffix.length().to_uint64(),
    (offset, length) => {
      calls.push((offset, length))
      assert_true(offset >= at)
      let relative = offset - at
      let body = payload + suffix
      body[relative.to_int():relative.to_int() + length].to_owned()
    },
  )
  let imported = @archive.SourceEmbeddedArchive::open_at(source, at)
  assert_eq(imported.prefix.size, at)
  assert_eq(imported.offset, at)
  assert_true(calls.all(call => call.0 >= at))
  assert_eq(imported.archive.verify().bytes, 14550UL)
  assert_eq(imported.suffix.read_at(0UL, suffix.length()), suffix)
  assert_true(
    imported.inventory_json() is { "offset": String("4294967303"), .. },
  )
  let before = calls.length()
  assert_true(
    try {
      ignore(
        @archive.SourceEmbeddedArchive::open(source, max_source_bytes=32UL),
      )
      false
    } catch {
      @archive.SourceLimit(..) => true
      _ => false
    },
  )
  assert_eq(calls.length(), before)
}
