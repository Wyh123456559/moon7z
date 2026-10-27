///|
fn lzma_raw_fixture() -> Bytes raise ArchiveError {
  let archive = Archive::open(lzma_private)
  let start = 32 + archive.streams.pack_offset
  archive.input[start:start + archive.streams.pack_sizes[0]].to_owned()
}

///|
test "LZMA1 accepts every legal property byte while malformed properties remain invalid" {
  for value in 0..<225 {
    let properties = Bytes::from_array([
      value.to_byte(),
      b'\x00',
      b'\x00',
      b'\x01',
      b'\x00',
    ])
    assert_eq(
      lzma_properties(properties),
      (value % 9, value / 9 % 5, value / 45),
    )
  }
  for
    properties in [
      b"", b"\x5d", b"\x5d\x00\x10\x00\x00\x00", b"\xe1\x00\x10\x00\x00", b"\xff\x00\x10\x00\x00",
    ] {
    let refused = try {
      ignore(lzma_properties(properties))
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(refused)
  }
  for value in [0, 224] {
    let properties = Bytes::from_array([
      value.to_byte(),
      b'\x00',
      b'\x10',
      b'\x00',
      b'\x00',
    ])
    assert_eq(
      decode_lzma1(b"\x00".repeat(5), 0, properties, Limits::new()),
      b"",
    )
  }
}

///|
test "LZMA1 packed tails truncated input history and resource defects never produce partial output" {
  let packed = lzma_raw_fixture()
  let properties = b"\xe0\x00\x00\x01\x00"
  for size in [0, 1, 4, 5, packed.length() / 2, packed.length() - 1] {
    let refused = try {
      ignore(
        decode_lzma1(packed[:size].to_owned(), 14229, properties, Limits::new()),
      )
      false
    } catch {
      Codec(..) => true
      _ => false
    }
    assert_true(refused)
  }
  for
    bytes in [
      packed + b"\x00",
      b"\x01\x00\x00\x00\x00",
      b"\x00\xff\xff\xff\xff",
    ] {
    let refused = try {
      ignore(decode_lzma1(bytes, 14229, properties, Limits::new()))
      false
    } catch {
      Codec(..) => true
      _ => false
    }
    assert_true(refused)
  }
  assert_eq(
    decode_lzma1(packed, 14229, properties, Limits::new()).length(),
    14229,
  )
  let limited = try {
    ignore(
      decode_lzma1(packed, 14229, properties, Limits::new(working_bytes=14228)),
    )
    false
  } catch {
    Limit(..) => true
    _ => false
  }
  assert_true(limited)
}

///|
test "LZMA1 history accepts the last dictionary byte and rejects unavailable history" {
  let model : LzmaModel = {
    range: {
      input: Cursor::new(b""),
      probabilities: FixedArray::make(0, 1024U),
      code: 0U,
      range: 0xffffffffU,
    },
    output: FixedArray::make(65537, b'a'),
    dictionary: 65536U,
    lc: 0,
    lp: 0,
    pb: 0,
    reps: FixedArray::make(4, 65535U),
    state: 0,
    position: 65536,
  }
  assert_eq(model.history(), b'a')
  model.reps[0] = 65536U
  let out_of_dictionary = try {
    ignore(model.history())
    false
  } catch {
    Codec(..) => true
    _ => false
  }
  assert_true(out_of_dictionary)
  model.reps[0] = 65535U
  model.position = 65535
  let unavailable = try {
    ignore(model.history())
    false
  } catch {
    Codec(..) => true
    _ => false
  }
  assert_true(unavailable)
  let mut seed = 0x12345678U
  for trial in 0..<256 {
    let input = @buffer.Buffer()
    input.write_byte(b'\x00')
    for _ in 0..<(4 + trial % 31) {
      seed = seed * 1664525U + 1013904223U
      input.write_byte((seed >> 24).to_byte())
    }
    let result = Some(
      decode_lzma1(
        input.to_bytes(),
        128,
        b"\x5d\x00\x10\x00\x00",
        Limits::new(),
      ),
    ) catch {
      _ => None
    }
    if result is Some(bytes) {
      assert_eq(bytes.length(), 128)
    }
  }
}
