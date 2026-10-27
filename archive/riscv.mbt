///|
/// RISC-V decoder adapted from Igor Pavlov's Bra.c, 7-Zip 26.05,
/// 2024-01-20, Public Domain. Scalar UInt32 version of the 16-bit scan path.
fn riscv_word(
  bytes : Array[Byte],
  start : Int32,
  big~ : Bool = false,
) -> UInt32 {
  let mut result = 0U
  for i in 0..<4 {
    let shift = if big { (3 - i) * 8 } else { i * 8 }
    result = result | (bytes[start + i].to_uint() << shift)
  }
  result
}

///|
fn riscv_store(bytes : Array[Byte], start : Int32, word : UInt32) -> Unit {
  for i in 0..<4 {
    bytes[start + i] = (word >> (i * 8)).to_byte()
  }
}

///|
fn riscv_decode(input : Bytes, initial : UInt32) -> Bytes {
  let bytes = input.to_array()
  // The SDK deliberately leaves a six/seven-byte tail for lookahead.
  let limit = bytes.length() / 2 * 2 - 6
  let mut position = 0
  while position < limit {
    let low = bytes[position].to_uint() | (bytes[position + 1].to_uint() << 8)
    let mut a = (low ^ 0x10U) + 1U
    if (a & 0x77U) != 0U {
      position += 2
      continue
    }
    let pc = initial + position.reinterpret_as_uint()
    if (a & 8U) == 0U {
      a -= 0x81U
      if (a & 0xd80U) != 0U {
        position += 2
        continue
      }
      let old = (a + 0x70U) & 0xfffU
      let absolute = (bytes[position + 3].to_uint() << 1) |
        (bytes[position + 2].to_uint() << 9) |
        ((a & 0xf000U) << 5)
      let relative = absolute - pc
      let word = old |
        ((relative << 11) & 0x80000000U) |
        ((relative << 20) & 0x7fe00000U) |
        ((relative << 9) & 0x100000U) |
        (relative & 0xff000U)
      riscv_store(bytes, position, word)
      position += 4
      continue
    }
    let v = a
    a = a |
      (bytes[position + 2].to_uint() << 16) |
      (bytes[position + 3].to_uint() << 24)
    if (v & 0xe80U) == 0U {
      let register = a >> 27
      if (v - 0x3108U) << 18 < (register & 0x1dU) {
        let relative = riscv_word(bytes, position + 4, big=true) - pc
        let second = (a >> 12) | (relative << 20)
        let first = (register << 7) +
          0x17U +
          ((relative + 0x800U) & 0xfffff000U)
        riscv_store(bytes, position, first)
        riscv_store(bytes, position + 4, second)
        position += 8
      } else {
        position += 4
      }
    } else {
      let next = riscv_word(bytes, position + 4)
      if (((next - 3U) ^ (v << 8)) & 0xf8003U) != 0U {
        position += 6
      } else {
        let second = (a & 0xfffff000U) | (next >> 20)
        let first = (next << 12) | 0x117U
        riscv_store(bytes, position, first)
        riscv_store(bytes, position + 4, second)
        position += 8
      }
    }
  }
  Bytes::from_array(bytes)
}
