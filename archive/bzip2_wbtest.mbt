///|
test "BZip2 RLE expansion exceeds block size safely and concatenated streams retain all data" {
  assert_eq(decode_bzip2(bzip_raw_runs, 1100000, 100000), b"a".repeat(1100000))
  let refused = try {
    ignore(decode_bzip2(bzip_raw_runs, 1000, 100000))
    false
  } catch {
    Codec(..) => true
    _ => false
  }
  assert_true(refused)
  let empty = b"BZh1\x17\x72\x45\x38\x50\x90\x00\x00\x00\x00"
  assert_eq(decode_bzip2(empty, 0, 100000), b"")
  let expected = Bytes::makei(1536, i => (i % 251).to_byte())
  assert_eq(
    decode_bzip2(bzip_randomized + empty + bzip_randomized, 3072, 100000),
    expected + expected,
  )
  assert_eq(decode_bzip2(bzip_raw_runs, 1100000, 100000), b"a".repeat(1100000))
}

///|
test "BZip2 randomized legacy blocks truncation metadata corruption and trailing data" {
  let expected = Bytes::makei(1536, i => (i % 251).to_byte())
  assert_eq(decode_bzip2(bzip_randomized, 1536, 100000), expected)
  for length in 0..<bzip_randomized.length() {
    let refused = try {
      ignore(decode_bzip2(bzip_randomized[:length].to_owned(), 1536, 100000))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  for index in [0, 3, 4, 10, bzip_randomized.length() - 1] {
    let changed = bzip_randomized.to_array()
    changed[index] = (changed[index].to_int() ^ 128).to_byte()
    let refused = try {
      ignore(decode_bzip2(Bytes::from_array(changed), 1536, 100000))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  let trailing = try {
    ignore(decode_bzip2(bzip_randomized + b"\x00", 1536, 100000))
    false
  } catch {
    _ => true
  }
  assert_true(trailing)
  let tree = try {
    ignore(BzipTree::new([1, 1, 1]))
    false
  } catch {
    Codec(..) => true
    _ => false
  }
  assert_true(tree)
  let props = try {
    validate_coder({ codec_id: b"\x04\x02\x02", properties: b"\x00", })
    false
  } catch {
    Invalid(..) => true
    _ => false
  }
  assert_true(props)
  let pointer = bzip_randomized.to_array()
  pointer[14] = b'\xff'
  pointer[15] = b'\xff'
  pointer[16] = b'\xff'
  pointer[17] = (pointer[17].to_int() | 128).to_byte()
  let invalid_pointer = try {
    ignore(decode_bzip2(Bytes::from_array(pointer), 1536, 100000))
    false
  } catch {
    Codec(..) => true
    _ => false
  }
  assert_true(invalid_pointer)
  assert_eq(decode_bzip2(bzip_randomized, 1536, 100000), expected)
}

///|
test "BZip2 combined CRC covers each independently decoded block" {
  let input : BzipBits = { data: bzip_raw_blocks, pos: 0, bits: 0UL, count: 0, }
  assert_eq(input.read(24), 0x425a68)
  assert_eq(input.read(8), 49)
  let output : Array[Byte] = []
  let mut combined = 0U
  let mut count = 0
  for ;; {
    let magic = input.magic()
    if magic == 0x177245385090UL {
      assert_eq(input.u32(), combined)
      break
    }
    assert_eq(magic, 0x314159265359UL)
    let crc = decode_bzip_block(input, 100000, output, 210123)
    combined = ((combined << 1) | (combined >> 31)) ^ crc
    count += 1
  }
  assert_eq(count, 3)
  assert_eq(
    Bytes::from_array(output),
    Bytes::makei(210123, i => ((i * 73 + i / 257) & 255).to_byte()),
  )
  let changed = bzip_raw_blocks.to_array()
  changed[changed.length() - 1] = (changed[changed.length() - 1].to_int() ^ 128).to_byte()
  let refused = try {
    ignore(decode_bzip2(Bytes::from_array(changed), 210123, 100000))
    false
  } catch {
    Checksum(..) => true
    _ => false
  }
  assert_true(refused)
}
