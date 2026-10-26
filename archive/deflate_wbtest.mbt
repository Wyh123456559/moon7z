///|
priv struct DeflateWriter {
  bits : Array[Int32]
}

///|
fn DeflateWriter::number(
  self : DeflateWriter,
  value : Int32,
  width : Int32,
) -> Unit {
  for i in 0..<width {
    self.bits.push((value >> i) & 1)
  }
}

///|
fn DeflateWriter::code(self : DeflateWriter, symbol : Int32) -> Unit {
  let (value, width) = if symbol < 144 {
    (symbol + 48, 8)
  } else if symbol < 256 {
    (symbol - 144 + 400, 9)
  } else if symbol < 280 {
    (symbol - 256, 7)
  } else {
    (symbol - 280 + 192, 8)
  }
  for i in 0..<width {
    self.bits.push((value >> (width - 1 - i)) & 1)
  }
}

///|
fn DeflateWriter::distance(self : DeflateWriter, symbol : Int32) -> Unit {
  for i in 0..<5 {
    self.bits.push((symbol >> (4 - i)) & 1)
  }
}

///|
fn DeflateWriter::bytes(self : DeflateWriter) -> Bytes {
  Bytes::makei((self.bits.length() + 7) / 8, i => {
    let mut byte = 0
    for bit in 0..<8 {
      if i * 8 + bit < self.bits.length() {
        byte = byte | (self.bits[i * 8 + bit] << bit)
      }
    }
    byte.to_byte()
  })
}

///|
test "DEFLATE stored and fixed literal alphabets exact lengths truncation and trailing data" {
  assert_eq(decode_deflate(b"\x01\x03\x00\xfc\xffabc", 3), b"abc")
  assert_eq(decode_deflate(b"\x03\x00", 0), b"")
  let writer : DeflateWriter = { bits: [], }
  writer.number(3, 3)
  for symbol in 0..<256 {
    writer.code(symbol)
  }
  writer.code(256)
  let bytes = writer.bytes()
  let expected = Bytes::makei(256, i => i.to_byte())
  assert_eq(decode_deflate(bytes, 256), expected)
  for size in [255, 257] {
    let refused = try {
      ignore(decode_deflate(bytes, size))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  for length in 0..<bytes.length() {
    let refused = try {
      ignore(decode_deflate(bytes[:length].to_owned(), 256))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  for malformed in [bytes + b"\x00", b"\x07", b"\x01\x03\x00\xfd\xffabc"] {
    let refused = try {
      ignore(decode_deflate(malformed, 256))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  assert_eq(decode_deflate(bytes, 256), expected)
}

///|
test "DEFLATE overlapping matches full window and cross-block history" {
  let writer : DeflateWriter = { bits: [], }
  writer.number(3, 3)
  for i in 0..<32768 {
    writer.code(i & 255)
  }
  writer.code(285) // length 258
  writer.distance(29)
  writer.number(8191, 13) // distance 32768
  writer.code(256)
  assert_eq(
    decode_deflate(writer.bytes(), 33026),
    Bytes::makei(33026, i => (i & 255).to_byte()),
  )
  let overlap : DeflateWriter = { bits: [], }
  overlap.number(3, 3)
  overlap.code(97)
  overlap.code(285)
  overlap.distance(0)
  overlap.code(256)
  assert_eq(decode_deflate(overlap.bytes(), 259), b"a".repeat(259))
  let next : DeflateWriter = { bits: [], }
  next.number(3, 3)
  next.code(257) // length 3, distance 3
  next.distance(2)
  next.code(256)
  assert_eq(
    decode_deflate(b"\x00\x03\x00\xfc\xffabc" + next.bytes(), 6),
    b"abcabc",
  )
}

///|
test "DEFLATE reserved symbols history before start and invalid trees fail safely" {
  for kind in 0..<3 {
    let writer : DeflateWriter = { bits: [], }
    writer.number(3, 3)
    if kind == 0 {
      writer.code(286)
    } else {
      if kind == 2 {
        writer.code(97)
      }
      writer.code(257)
      writer.distance(if kind == 2 { 30 } else { 0 })
    }
    writer.code(256)
    let refused = try {
      ignore(decode_deflate(writer.bytes(), 10))
      false
    } catch {
      Codec(..) => true
      _ => false
    }
    assert_true(refused)
  }
  for lengths in [[1, 1, 1], [2, 2], [0, 0]] {
    let refused = try {
      ignore(DeflateTree::new(lengths, code_lengths=true))
      false
    } catch {
      Codec(..) => true
      _ => false
    }
    assert_true(refused)
  }
  validate_coder({ codec_id: b"\x04\x01\x08", properties: b"", })
  let props = try {
    validate_coder({ codec_id: b"\x04\x01\x08", properties: b"\x00", })
    false
  } catch {
    Invalid(..) => true
    _ => false
  }
  assert_true(props)
}

///|
test "dynamic DEFLATE permits an unused empty distance tree and rejects invalid repeats" {
  for variant in 0..<4 {
    let writer : DeflateWriter = { bits: [], }
    writer.number(5, 3) // final, dynamic
    writer.number(0, 5) // 257 literal/length symbols
    writer.number(0, 5) // one distance symbol
    writer.number(14, 4) // eighteen code-length symbols
    // Canonical alphabet: 18 (or 16) = 0, 0 = 10, 1 = 11.
    let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1]
    for symbol in order {
      writer.number(
        if symbol == (if variant == 1 { 16 } else { 18 }) {
          1
        } else if symbol == 0 || symbol == 1 {
          2
        } else {
          0
        },
        3,
      )
    }
    writer.number(0, 1)
    if variant != 1 {
      writer.number(127, 7) // 138 zeros
      writer.number(0, 1)
      writer.number(
        if variant == 2 {
          127
        } else if variant == 3 {
          108
        } else {
          107
        },
        7,
      )
      writer.number(3, 2) // code 11: length one
      if variant != 3 {
        writer.number(1, 2)
      } // code 10: distance tree unused
      writer.number(0, 1) // sole EOB code
    }
    if variant == 0 {
      assert_eq(decode_deflate(writer.bytes(), 0), b"")
    } else {
      let refused = try {
        ignore(decode_deflate(writer.bytes(), 0))
        false
      } catch {
        Codec(..) => true
        _ => false
      }
      assert_true(refused)
    }
  }
}
