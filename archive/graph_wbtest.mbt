///|
test "graph order and packed order are independent and final output need not be last stored" {
  let layout = read_pipeline(
    Cursor::new(
      b"\x02\x14\x03\x03\x01\x1b\x04\x01\x01\x00\x00\x01\x04\x01\x02\x03",
    ),
  )
  assert_eq(layout.order, [1, 0])
  assert_eq(layout.final_output, 0)
  layout.sizes[0] = 3
  layout.sizes[1] = 3
  validate_graph_sizes(layout, [3, 0, 0, 5])
  assert_eq(
    decode_graph(layout, [b"abc", b"", b"", b"\x00".repeat(5)], Limits::new()),
    b"abc",
  )
  // Reorder the four physical inputs without changing their logical roles.
  let swapped = read_pipeline(
    Cursor::new(b"\x01\x14\x03\x03\x01\x1b\x04\x01\x03\x02\x01\x00"),
  )
  swapped.sizes[0] = 3
  validate_graph_sizes(swapped, [5, 0, 0, 3])
  assert_eq(
    decode_graph(swapped, [b"\x00".repeat(5), b"", b"", b"abc"], Limits::new()),
    b"abc",
  )
}

///|
test "all physical input CRCs and grouped offsets are checked across folders" {
  let copy = read_pipeline(Cursor::new(b"\x01\x01\x00"))
  copy.sizes[0] = 1
  let bcj2 = read_pipeline(
    Cursor::new(b"\x01\x14\x03\x03\x01\x1b\x04\x01\x00\x01\x02\x03"),
  )
  bcj2.sizes[0] = 3
  bcj2.pack_start = 1
  let controls = b"\x00".repeat(5)
  let streams : Streams = {
    pack_offset: 0,
    pack_sizes: [1, 3, 0, 0, 5],
    pack_crcs: [
      Some(crc32(b"z")),
      Some(crc32(b"abc")),
      Some(0U),
      Some(0U),
      Some(crc32(controls)),
    ],
    blocks: [
      {
        coders: copy.nodes,
        size: 1,
        crc: Some(crc32(b"z")),
        pieces: [(1, Some(crc32(b"z")))],
      },
      {
        coders: bcj2.nodes,
        size: 3,
        crc: Some(crc32(b"abc")),
        pieces: [(3, Some(crc32(b"abc")))],
      },
    ],
    layouts: [copy, bcj2],
  }
  let input = b"\x00".repeat(32) + b"zabc" + controls
  assert_eq(decode_streams(input, streams, Limits::new()), [b"z", b"abc"])
  for index in 1..<5 {
    let correct = streams.pack_crcs[index].unwrap()
    streams.pack_crcs[index] = Some(correct ^ 1U)
    let refused = try {
      ignore(decode_streams(input, streams, Limits::new()))
      false
    } catch {
      Checksum(..) => true
      _ => false
    }
    assert_true(refused)
    streams.pack_crcs[index] = Some(correct)
  }
  assert_eq(decode_streams(input, streams, Limits::new()), [b"z", b"abc"])
}

///|
test "BCJ2 arity properties packed duplicates and bound packed indices are rejected" {
  for
    bytes in [
      b"\x01\x04\x03\x03\x01\x1b", b"\x01\x14\x03\x03\x01\x1b\x03\x01", b"\x01\x14\x03\x03\x01\x1b\x04\x02",
      b"\x01\x34\x03\x03\x01\x1b\x04\x01\x01\x00", b"\x01\x14\x03\x03\x01\x1b\x04\x01\x00\x01\x02\x02",
      b"\x02\x14\x03\x03\x01\x1b\x04\x01\x01\x00\x00\x01\x00\x01\x02\x03",
    ] {
    let refused = try {
      ignore(read_pipeline(Cursor::new(bytes)))
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(refused)
  }
  let refused = try {
    ignore(read_pipeline(Cursor::new(b"\x02"), limits=Limits::new(coders=1)))
    false
  } catch {
    Limit(..) => true
    _ => false
  }
  assert_true(refused)
}

///|
test "BCJ2 validates every input consumes it exactly and recovers after errors" {
  let valid = [b"\xe8", b"\x00\x00\x00\x05", b"", b"\x00\x7f\xff\xfc\x00"]
  assert_eq(decode_bcj2(valid, 5), b"\xe8\x00\x00\x00\x00")
  assert_eq(
    decode_bcj2([b"\xe9", b"", valid[1], valid[3]], 5),
    b"\xe9\x00\x00\x00\x00",
  )
  assert_eq(
    decode_bcj2([b"\x0f\x85", b"", b"\x00\x00\x00\x06", valid[3]], 6),
    b"\x0f\x85\x00\x00\x00\x00",
  )
  assert_eq(decode_bcj2([b"", b"", b"", b"\x00".repeat(5)], 0), b"")
  for input in 0..<4 {
    for length in 0..<valid[input].length() {
      let changed = valid.copy()
      changed[input] = valid[input][:length].to_owned()
      let refused = try {
        ignore(decode_bcj2(changed, 5))
        false
      } catch {
        _ => true
      }
      assert_true(refused)
    }
    let extra = valid.copy()
    extra[input] += b"\x00"
    let refused = try {
      ignore(decode_bcj2(extra, 5))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  for
    control in [
      b"\x01\x00\x00\x00\x00", b"\x00\xff\xff\xff\xff", b"\x00\x7f\xff\xfc\x01",
    ] {
    let refused = try {
      ignore(decode_bcj2([valid[0], valid[1], valid[2], control], 5))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  let overflow = try {
    ignore(decode_bcj2(valid, 4))
    false
  } catch {
    Invalid(..) => true
    _ => false
  }
  assert_true(overflow)
  assert_eq(decode_bcj2(valid, 5), b"\xe8\x00\x00\x00\x00")
}
