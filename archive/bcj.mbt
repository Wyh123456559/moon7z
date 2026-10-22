///|
/// Adapted from Igor Pavlov's Public Domain Bra86.c (2021-02-09),
/// 7-Zip 21.07. See SOURCES.md. Decode the complete solid folder in one pass;
/// incomplete trailing instructions are copied without interpretation.
fn bcj_decode(input : Bytes, start_offset~ : UInt32 = 0U) -> Bytes {
  if input.length() < 5 {
    return input
  }
  let data = input.to_array()
  let limit = data.length() - 4
  let mut pos = 0
  let mut mask = 0U
  while pos < limit {
    let previous = pos
    while pos < limit && (data[pos].to_int() & 0xfe) != 0xe8 {
      pos += 1
    }
    if pos >= limit {
      break
    }
    let distance = pos - previous
    if distance > 2 {
      mask = 0U
    } else {
      mask = mask >> distance
      if mask != 0U &&
        (
          mask > 4U ||
          mask == 3U ||
          bcj_msbyte(data[pos + (mask >> 1).reinterpret_as_int() + 1])
        ) {
        mask = (mask >> 1) | 4U
        pos += 1
        continue
      }
    }
    if bcj_msbyte(data[pos + 4]) {
      let mut value = data[pos + 1].to_int().reinterpret_as_uint() |
        (data[pos + 2].to_int().reinterpret_as_uint() << 8) |
        (data[pos + 3].to_int().reinterpret_as_uint() << 16) |
        (data[pos + 4].to_int().reinterpret_as_uint() << 24)
      let ip = start_offset + pos.reinterpret_as_uint() + 5U
      value -= ip
      if mask != 0U {
        let shift = ((mask & 6U) << 2).reinterpret_as_int()
        if bcj_msbyte((value >> shift).to_byte()) {
          value = (value ^ ((0x100U << shift) - 1U)) - ip
        }
        mask = 0U
      }
      data[pos + 1] = value.to_byte()
      data[pos + 2] = (value >> 8).to_byte()
      data[pos + 3] = (value >> 16).to_byte()
      // Sign extension is from bit 24, not the host sign bit (bit 31).
      data[pos + 4] = (0U - ((value >> 24) & 1U)).to_byte()
      pos += 5
    } else {
      mask = (mask >> 1) | 4U
      pos += 1
    }
  }
  Bytes::from_array(data)
}

///|
fn bcj_msbyte(byte : Byte) -> Bool {
  byte == b'\x00' || byte == b'\xff'
}
