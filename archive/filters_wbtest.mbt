///|
test "linear bindings resolve decode order independently of stored order" {
  let pipeline = read_pipeline(
    Cursor::new(b"\x02\x21\x03\x01\x03\x01\x00\x00\x01"),
  )
  assert_eq(pipeline.ordered_coders().length(), 2)
  assert_eq(pipeline.ordered_coders()[0].codec_id, b"\x00")
  assert_eq(pipeline.ordered_coders()[1].codec_id, b"\x03")
  let chain : Block = {
    coders: read_pipeline(
      Cursor::new(
        b"\x03\x21\x03\x01\x03\x21\x03\x01\x00\x01\x00\x00\x01\x01\x02",
      ),
    ).ordered_coders(),
    size: 8,
    crc: Some(crc32(b"abcdefgh")),
    pieces: [],
  }
  assert_eq(
    decode(chain, b"a\x01\x01\x01\xa0\x00\x00\x00", Limits::new()),
    b"abcdefgh",
  )
  let maximum = @buffer.Buffer()
  maximum.write_bytes(b"\x08\x01\x00")
  for _ in 0..<7 {
    maximum.write_bytes(b"\x21\x03\x01\x00")
  }
  for i in 1..<8 {
    maximum.write_byte(i.to_byte())
    maximum.write_byte((i - 1).to_byte())
  }
  assert_eq(
    read_pipeline(Cursor::new(maximum.to_bytes())).ordered_coders().length(),
    8,
  )
}

///|
test "coder graphs reject duplicate edges cycles disconnected nodes and unsafe sizes" {
  for
    bytes in [
      b"\x00", b"\x09", b"\x02\x01\x00\x01\x00\x00\x00", b"\x02\x01\x00\x01\x00\x02\x00",
      b"\x03\x01\x00\x01\x00\x01\x00\x01\x00\x01\x02", b"\x03\x01\x00\x01\x00\x01\x00\x01\x00\x02\x00",
      b"\x03\x01\x00\x01\x00\x01\x00\x01\x02\x02\x01", b"\x01\x11\x00\x02\x01",
    ] {
    let rejected = try {
      ignore(read_pipeline(Cursor::new(bytes)))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "all intermediate outputs must match the bounded final output" {
  let prefix = b"\x06\x00\x01\x09\x01\x00\x07\x0b\x01\x00\x02\x21\x03\x01\x00\x01\x00\x00\x01\x0c"
  let valid = read_streams(
    Cursor::new(prefix + b"\x01\x01\x00\x00"),
    Limits::new(),
    1,
  )
  assert_eq(valid.blocks[0].size, 1)
  for sizes in [b"\x01\x00", b"\x00\x01", b"\x01\x02", b"\x02\x01"] {
    let rejected = try {
      ignore(
        read_streams(
          Cursor::new(prefix + sizes + b"\x00\x00"),
          Limits::new(),
          1,
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "Delta distances short inputs and chained filters reconstruct whole folders" {
  for distance in [1, 2, 4, 255, 256] {
    for length in [0, 1, distance - 1, distance, distance + 1, 1025] {
      let original = Bytes::makei(length, i => {
        ((i * 37 + i / 3) & 255).to_byte()
      })
      // An independent encoder, not the decoder dependency's inverse.
      let encoded = Bytes::makei(length, i => {
        let previous = if i >= distance {
          original[i - distance].to_int()
        } else {
          0
        }
        ((original[i].to_int() - previous) & 255).to_byte()
      })
      let block : Block = {
        coders: [
          { codec_id: b"\x00", properties: b"", },
          {
            codec_id: b"\x03",
            properties: Bytes::from_array([(distance - 1).to_byte()]),
          },
        ],
        size: length,
        crc: Some(crc32(original)),
        pieces: [],
      }
      assert_eq(
        decode(block, encoded, Limits::new(dictionary_bytes=0)),
        original,
      )
    }
  }
  for props in [b"", b"\x00\x00"] {
    let rejected = try {
      validate_coder({ codec_id: b"\x03", properties: props, })
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(rejected)
  }
  let wrong_crc : Block = {
    coders: [
      { codec_id: b"\x00", properties: b"", },
      { codec_id: b"\x03", properties: b"\x00", },
    ],
    size: 3,
    crc: Some(crc32(b"abc") ^ 1U),
    pieces: [],
  }
  let rejected = try {
    ignore(decode(wrong_crc, b"a\x01\x01", Limits::new()))
    false
  } catch {
    Checksum(..) => true
    _ => false
  }
  assert_true(rejected)
}
