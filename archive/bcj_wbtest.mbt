///|
test "BCJ sign extends bit 24 rather than bit 31" {
  assert_eq(bcj_decode(b"\xe8\x00\x00\x00\xff"), b"\xe8\xfb\xff\xff\x00")
  assert_eq(bcj_decode(b"\xe9\x05\x00\x00\x00"), b"\xe9\x00\x00\x00\x00")
  assert_eq(
    bcj_decode(b"\xe8\x00\x00\x00\x00", start_offset=0xfffffffcU),
    b"\xe8\xff\xff\xff\xff",
  )
  assert_eq(
    bcj_decode(b"\xe8\x00\x00\x00\x00", start_offset=0x1000000U),
    b"\xe8\xfb\xff\xff\x00",
  )
}

///|
test "BCJ preserves short tails non-branch bytes and noncanonical immediates" {
  for length in 0..<5 {
    let bytes = b"\xe8\xe9\xff\x00"[:length].to_owned()
    assert_eq(bcj_decode(bytes), bytes)
  }
  for
    bytes in [
      b"\xe8\x00\x00\x00\x12", b"\x90\xe8\xff\x00", b"\xe7\x00\x00\x00\x00",
    ] {
    assert_eq(bcj_decode(bytes), bytes)
  }
}

///|
test "BCJ2 unknown aliases and BCJ properties are explicitly refused" {
  validate_coder({ codec_id: b"\x03\x03\x01\x03", properties: b"", })
  for
    coder in [
      { codec_id: b"\x03\x03\x01\x03", properties: b"\x00", },
      { codec_id: b"\x03\x03\x01\x03", properties: b"\x00\x00\x00\x00", },
      { codec_id: b"\x03\x03\x01\x1b", properties: b"", },
      { codec_id: b"\x04", properties: b"", },
    ] {
    let rejected = try {
      validate_coder(coder)
      false
    } catch {
      Unsupported(..) => true
      _ => false
    }
    assert_true(rejected)
  }
}
