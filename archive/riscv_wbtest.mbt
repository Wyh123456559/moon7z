///|
test "RISC-V properties distinguish two-byte alignment and refuse malformed offsets" {
  for
    properties in [
      b"", b"\x00\x00\x00\x00", b"\x02\x00\x00\x00", b"\xfe\xff\xff\xff",
    ] {
    let coder : Coder = { codec_id: b"\x0b", properties, }
    validate_coder(coder)
    validate_dictionary(coder, Limits::new(dictionary_bytes=0))
  }
  for
    properties in [
      b"\x00", b"\x00\x00", b"\x00\x00\x00", b"\x00\x00\x00\x00\x00", b"\x01\x00\x00\x00",
      b"\xff\xff\xff\xff",
    ] {
    let failed = try {
      validate_coder({ codec_id: b"\x0b", properties, })
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(failed)
  }
}

///|
test "RISC-V bounded scan keeps short input and handles PC wrap and AUIPC reconstruction" {
  for length in 0..<8 {
    let bytes = b"\xef\x00\x00\x01\x17\x31\x00\x08"[:length].to_owned()
    assert_eq(riscv_decode(bytes, 0U), bytes)
  }
  let encoded = b"\xef\x00\x00\x01\x01\x00\x01\x00"
  assert_eq(riscv_decode(encoded, 0U), b"\xef\x00\x20\x00\x01\x00\x01\x00")
  assert_eq(riscv_decode(encoded, 2U), b"\xef\x00\x00\x00\x01\x00\x01\x00")
  assert_eq(
    riscv_decode(encoded, 0xfffffffeU),
    b"\xef\x00\x40\x00\x01\x00\x01\x00",
  )
  assert_eq(
    riscv_decode(b"\x17\x31\x00\x08\x00\x00\x10\x01", 0U),
    b"\x97\x10\x00\x00\x03\x80\x10\x00",
  )
  for length in 0..<256 {
    let input = Bytes::makei(length, i => ((i * 37 + length) & 255).to_byte())
    for offset in [0U, 2U, 0xfffffffeU] {
      let output = riscv_decode(input, offset)
      assert_eq(output.length(), length)
      assert_eq(output, riscv_decode(input, offset))
    }
  }
}
