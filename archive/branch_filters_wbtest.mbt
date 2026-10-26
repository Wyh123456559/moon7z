///|
test "classic branch methods reject nonempty properties and require no dictionary" {
  for
    id in [
      b"\x03\x03\x05\x01", b"\x03\x03\x07\x01", b"\x03\x03\x02\x05", b"\x03\x03\x04\x01",
      b"\x03\x03\x08\x05",
    ] {
    let coder : Coder = { codec_id: id, properties: b"", }
    validate_coder(coder)
    validate_dictionary(coder, Limits::new(dictionary_bytes=0))
    assert_true(is_filter(id))
    for properties in [b"\x00", b"\x00\x00\x00\x00", b"\xf0\xff\xff\xff"] {
      let error = try {
        validate_coder({ codec_id: id, properties, })
        None
      } catch {
        err => Some(err)
      }
      assert_true(error is Some(Unsupported(..)))
    }
    for length in 0..<66 {
      let input = Bytes::make(length, b'\xaa')
      let block : Block = {
        coders: [{ codec_id: b"\x00", properties: b"", }, coder],
        size: length,
        crc: Some(crc32(input)),
        pieces: [],
      }
      assert_eq(decode(block, input, Limits::new(dictionary_bytes=0)), input)
    }
  }
}

///|
test "byte swaps preserve partial tails are involutions and can compose" {
  for width in [2, 4] {
    let id = if width == 2 { b"\x02\x03\x02" } else { b"\x02\x03\x04" }
    validate_coder({ codec_id: id, properties: b"", })
    for length in 0..<66 {
      let input = Bytes::makei(length, i => ((i * 7) & 255).to_byte())
      let swapped = swap_bytes(input, width)
      assert_eq(swapped.length(), input.length())
      assert_eq(swap_bytes(swapped, width), input)
      let end = length / width * width
      assert_eq(swapped[end:].to_owned(), input[end:].to_owned())
    }
    let error = try {
      validate_coder({ codec_id: id, properties: b"\x00", })
      None
    } catch {
      err => Some(err)
    }
    assert_true(error is Some(Invalid(..)))
  }
  assert_eq(swap_bytes(b"\x01\x02\x03", 2), b"\x02\x01\x03")
  let original = b"\x00\x01\x02\x03\x04\x05\x06"
  let packed = swap_bytes(swap_bytes(original, 4), 2)
  let block : Block = {
    coders: [
      { codec_id: b"\x00", properties: b"", },
      { codec_id: b"\x02\x03\x02", properties: b"", },
      { codec_id: b"\x02\x03\x04", properties: b"", },
    ],
    size: original.length(),
    crc: Some(crc32(original)),
    pieces: [],
  }
  assert_eq(decode(block, packed, Limits::new(dictionary_bytes=0)), original)
}
