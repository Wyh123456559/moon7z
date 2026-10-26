///|
/// BCJ2 range/branch decoding, adapted from Igor Pavlov's Bcj2.c/Bcj2.h
/// (7-Zip 26.05, 2023-03-01/02), Public Domain. Whole-folder, bounded output.
fn decode_bcj2(
  streams : Array[Bytes],
  size : Int32,
) -> Bytes raise ArchiveError {
  guard streams.length() == 4 && size >= 0 else {
    raise Invalid(
      offset=0,
      reason="BCJ2 requires four inputs and a bounded output size",
    )
  }
  guard streams[1].length() % 4 == 0 && streams[2].length() % 4 == 0 else {
    raise Invalid(
      offset=0,
      reason="BCJ2 address streams must contain complete UInt32 values",
    )
  }
  let main = Cursor::new(streams[0])
  let call = Cursor::new(streams[1])
  let jump = Cursor::new(streams[2])
  let control = Cursor::new(streams[3])
  guard control.byte() == 0 else {
    raise Codec(reason="invalid BCJ2 range prefix")
  }
  let mut code = 0U
  for _ in 0..<4 {
    code = (code << 8) | control.byte().reinterpret_as_uint()
  }
  guard code != 0xffffffffU else {
    raise Codec(reason="invalid BCJ2 initial range state")
  }
  let mut range = 0xffffffffU
  let probabilities = Array::make(258, 1024U)
  let output : Array[Byte] = Array(capacity=size)
  let mut previous = 0
  while output.length() < size {
    if range < 0x1000000U {
      range = range << 8
      code = (code << 8) | control.byte().reinterpret_as_uint()
    }
    let byte = main.byte()
    output.push(byte.to_byte())
    let candidate = (byte & 0xfe) == 0xe8 ||
      (previous == 0x0f && (byte & 0xf0) == 0x80)
    if !candidate {
      previous = byte
      continue
    }
    let index = if byte == 0xe8 {
      previous + 2
    } else if byte == 0xe9 {
      1
    } else {
      0
    }
    let probability = probabilities[index]
    let bound = (range >> 11) * probability
    if code < bound {
      range = bound
      probabilities[index] = probability + ((2048U - probability) >> 5)
      previous = byte
    } else {
      range -= bound
      code -= bound
      probabilities[index] = probability - (probability >> 5)
      guard size - output.length() >= 4 else {
        raise Invalid(
          offset=output.length(),
          reason="BCJ2 converted address exceeds declared output",
        )
      }
      let source = if byte == 0xe8 { call } else { jump }
      let mut address = 0U
      for _ in 0..<4 {
        address = (address << 8) | source.byte().reinterpret_as_uint()
      }
      let relative = address - (output.length().reinterpret_as_uint() + 4U)
      for shift in 0..<4 {
        output.push((relative >> (shift * 8)).to_byte())
      }
      previous = (relative >> 24).reinterpret_as_int()
    }
  }
  if range < 0x1000000U && control.pos < control.data.length() {
    code = (code << 8) | control.byte().reinterpret_as_uint()
  }
  main.end()
  call.end()
  jump.end()
  control.end()
  guard code == 0U else {
    raise Codec(reason="BCJ2 range stream did not finish cleanly")
  }
  Bytes::from_array(output)
}
