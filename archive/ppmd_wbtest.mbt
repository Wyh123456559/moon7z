///|
fn ppmd_input() -> Bytes raise ArchiveError {
  let archive = Archive::open(ppmd_internal)
  let start = 32 + archive.streams.pack_offset.to_int()
  archive.input[start:start + archive.streams.pack_sizes[0]].to_owned()
}

///|
test "PPMd7 allocator coalescing and exhaustion restart preserve every decoded byte" {
  let packed = ppmd_input()
  let input = Cursor::new(packed)
  assert_eq(input.byte(), 0)
  let mut code = 0U
  for _ in 0..<4 {
    code = (code << 8) | input.byte().reinterpret_as_uint()
  }
  let range : PpmRange = { input, code, range: 0xffffffffU, }
  let model = Ppm::new(16, 65536)
  for i in 0..<210123 {
    assert_eq(model.symbol(range), (i * 73 + i / 257) & 255)
  }
  input.end()
  assert_eq(range.code, 0U)
  assert_true(model._gluing > 0)
  assert_true(model._restarts > 1)
}

///|
test "PPMd7 properties and empty streams cover format limits including unaligned arenas" {
  for order in [2, 32, 64] {
    for size in [2048, 2049, 65536] {
      let p = @buffer.Buffer()
      p.write_byte(order.to_byte())
      p.write_uint_le(size.reinterpret_as_uint())
      assert_eq(
        decode_ppmd(b"\x00".repeat(5), 0, p.to_bytes(), Limits::new()),
        b"",
      )
    }
  }
  assert_eq(ppm_properties(b"\x40\xdb\xff\xff\xff"), (64, 0xffffffdbUL))
  for
    properties in [
      b"", b"\x01\x00\x00\x01\x00", b"\x41\x00\x00\x01\x00", b"\x02\xff\x07\x00\x00",
      b"\x02\xdc\xff\xff\xff", b"\x02\x00\x00\x01\x00\x00",
    ] {
    let refused = try {
      ignore(ppm_properties(properties))
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(refused)
  }
}

///|
test "PPMd7 truncations trailing bytes wrong sizes invalid range initialization and recovery are explicit" {
  let packed = ppmd_input()
  let properties = b"\x10\x00\x00\x01\x00"
  for length in [0, 1, 4, 5, 6, packed.length() / 2, packed.length() - 1] {
    let refused = try {
      ignore(
        decode_ppmd(
          packed[:length].to_owned(),
          210123,
          properties,
          Limits::new(),
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  for
    (bytes, size) in [
      (packed + b"\x00", 210123),
      (packed, 1),
      (packed, 420246),
      (b"\x01\x00\x00\x00\x00", 0),
      (b"\x00\xff\xff\xff\xff", 0),
    ] {
    let refused = try {
      ignore(decode_ppmd(bytes, size, properties, Limits::new()))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  assert_eq(
    decode_ppmd(packed, 210123, properties, Limits::new()).length(),
    210123,
  )
  let limited = try {
    ignore(
      decode_ppmd(
        packed,
        210123,
        properties,
        Limits::new(dictionary_bytes=65535),
      ),
    )
    false
  } catch {
    Limit(..) => true
    _ => false
  }
  assert_true(limited)
  let output_limited = try {
    ignore(
      decode_ppmd(packed, 210123, properties, Limits::new(working_bytes=210122)),
    )
    false
  } catch {
    Limit(resource="PPMd7 coder output bytes", ..) => true
    _ => false
  }
  assert_true(output_limited)
}

///|
test "PPMd7 malformed byte families fail through typed errors rather than unchecked arena access" {
  let mut seed = 0x12345678U
  for trial in 0..<512 {
    let bytes = @buffer.Buffer()
    bytes.write_byte(b'\x00')
    for _ in 0..<(4 + trial % 61) {
      seed = seed * 1664525U + 1013904223U
      bytes.write_byte((seed >> 24).to_byte())
    }
    let properties = if trial % 2 == 0 {
      b"\x40\x01\x08\x00\x00"
    } else {
      b"\x02\x00\x00\x01\x00"
    }
    let result = Some(
      decode_ppmd(bytes.to_bytes(), 256, properties, Limits::new()),
    ) catch {
      _ => None
    }
    if result is Some(output) {
      assert_eq(output.length(), 256)
    }
  }
}
