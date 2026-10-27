// Raw LZMA1 decoding adapted from aurora0x27/lzma-mbt, e50568f7d8358045c39092210d140f6a5eec6971,
// src/internal/coder/decode.mbt, helpers.mbt and internal/range_coder/range.mbt.
// Apache-2.0. See licenses/lzma-mbt-Apache-2.0.txt and SOURCES.md.
// This private decoder adds complete LZMA1 properties, a probability-table budget,
// exact packed consumption and explicit optional end-marker validation.

///|
priv struct LzmaInput {
  // Flat SDK probability layout: match 0, reps 192/204/216/228,
  // short reps 240, distance slots 432, modeled distances 688, alignment 802,
  // length models 818/1332 and literal contexts 1846.
  input : Cursor
  probabilities : FixedArray[UInt32]
  mut code : UInt32
  mut range : UInt32
}

///|
fn lzma_bad() -> ArchiveError {
  Codec(reason="invalid LZMA1 symbols, history or range termination")
}

///|
fn LzmaInput::normalize(self : LzmaInput) -> Unit raise ArchiveError {
  if self.range < 0x1000000U {
    self.code = (self.code << 8) | self.input.byte().reinterpret_as_uint()
    self.range = self.range << 8
  }
}

///|
fn LzmaInput::bit(self : LzmaInput, index : Int32) -> Int32 raise ArchiveError {
  guard index >= 0 && index < self.probabilities.length() else {
    raise lzma_bad()
  }
  let probability = self.probabilities[index]
  let bound = (self.range >> 11) * probability
  let result = if self.code < bound {
    self.range = bound
    self.probabilities[index] = probability + ((2048U - probability) >> 5)
    0
  } else {
    self.range -= bound
    self.code -= bound
    self.probabilities[index] = probability - (probability >> 5)
    1
  }
  self.normalize()
  result
}

///|
fn LzmaInput::tree(
  self : LzmaInput,
  base : Int32,
  bits : Int32,
  reverse~ : Bool = false,
) -> Int32 raise ArchiveError {
  let mut symbol = 1
  let mut value = 0
  for i in 0..<bits {
    let bit = self.bit(base + symbol)
    symbol = (symbol << 1) | bit
    value = value | (bit << i)
  }
  if reverse {
    value
  } else {
    symbol - (1 << bits)
  }
}

///|
fn LzmaInput::direct(
  self : LzmaInput,
  bits : Int32,
) -> UInt32 raise ArchiveError {
  let mut value = 0U
  for _ in 0..<bits {
    self.range = self.range >> 1
    value = value << 1
    if self.code >= self.range {
      self.code -= self.range
      value = value | 1U
    }
    self.normalize()
  }
  value
}

///|
fn LzmaInput::length(
  self : LzmaInput,
  base : Int32,
  state : Int32,
) -> Int32 raise ArchiveError {
  if self.bit(base) == 0 {
    2 + self.tree(base + 2 + state * 8, 3)
  } else if self.bit(base + 1) == 0 {
    10 + self.tree(base + 130 + state * 8, 3)
  } else {
    18 + self.tree(base + 258, 8)
  }
}

///|
fn LzmaInput::distance(
  self : LzmaInput,
  length : Int32,
) -> UInt32 raise ArchiveError {
  let state = if length < 6 { length - 2 } else { 3 }
  let slot = self.tree(432 + state * 64, 6)
  if slot < 4 {
    return slot.reinterpret_as_uint()
  }
  let bits = (slot >> 1) - 1
  let base = (2U | (slot.reinterpret_as_uint() & 1U)) << bits
  if slot < 14 {
    base +
    self
    .tree(688 + base.reinterpret_as_int() - slot - 1, bits, reverse=true)
    .reinterpret_as_uint()
  } else {
    base +
    (self.direct(bits - 4) << 4) +
    self.tree(802, 4, reverse=true).reinterpret_as_uint()
  }
}

///|
priv struct LzmaModel {
  range : LzmaInput
  output : FixedArray[Byte]
  dictionary : UInt32
  lc : Int32
  lp : Int32
  pb : Int32
  reps : FixedArray[UInt32]
  mut state : Int32
  mut position : Int32
}

///|
fn LzmaModel::history(self : LzmaModel) -> Byte raise ArchiveError {
  let distance = self.reps[0]
  guard distance < self.position.reinterpret_as_uint() &&
    distance < self.dictionary else {
    raise lzma_bad()
  }
  self.output[self.position - distance.reinterpret_as_int() - 1]
}

///|
fn LzmaModel::emit(self : LzmaModel, byte : Byte) -> Unit raise ArchiveError {
  guard self.position < self.output.length() else { raise lzma_bad() }
  self.output[self.position] = byte
  self.position += 1
}

///|
fn LzmaModel::symbol(
  self : LzmaModel,
  allow_end : Bool,
) -> Bool raise ArchiveError {
  let range = self.range
  let ps = self.position & ((1 << self.pb) - 1)
  if range.bit(self.state * 16 + ps) == 0 {
    let previous = if self.position == 0 {
      0
    } else {
      self.output[self.position - 1].to_int()
    }
    let context = ((self.position & ((1 << self.lp) - 1)) << self.lc) +
      (previous >> (8 - self.lc))
    let base = 1846 + context * 0x300
    let mut symbol = 1
    if self.state >= 7 {
      let mut matched = self.history().to_int()
      while symbol < 256 {
        let prediction = (matched >> 7) & 1
        matched = (matched << 1) & 255
        let bit = range.bit(base + ((1 + prediction) << 8) + symbol)
        symbol = (symbol << 1) | bit
        if prediction != bit {
          break
        }
      }
    }
    while symbol < 256 {
      symbol = (symbol << 1) | range.bit(base + symbol)
    }
    self.emit(symbol.to_byte())
    self.state = if self.state < 4 {
      0
    } else if self.state < 10 {
      self.state - 3
    } else {
      self.state - 6
    }
    return false
  }
  let length = if range.bit(192 + self.state) != 0 {
    if range.bit(204 + self.state) == 0 {
      if range.bit(240 + self.state * 16 + ps) == 0 {
        self.emit(self.history())
        self.state = if self.state < 7 { 9 } else { 11 }
        return false
      }
    } else {
      let distance = if range.bit(216 + self.state) == 0 {
        self.reps[1]
      } else {
        let value = if range.bit(228 + self.state) == 0 {
          self.reps[2]
        } else {
          let value = self.reps[3]
          self.reps[3] = self.reps[2]
          value
        }
        self.reps[2] = self.reps[1]
        value
      }
      self.reps[1] = self.reps[0]
      self.reps[0] = distance
    }
    let length = range.length(1332, ps)
    self.state = if self.state < 7 { 8 } else { 11 }
    length
  } else {
    self.reps[3] = self.reps[2]
    self.reps[2] = self.reps[1]
    self.reps[1] = self.reps[0]
    let length = range.length(818, ps)
    let distance = range.distance(length)
    if distance == 0xffffffffU {
      guard allow_end else {
        raise Codec(reason="LZMA1 end marker precedes declared output size")
      }
      return true
    }
    self.reps[0] = distance
    self.state = if self.state < 7 { 7 } else { 10 }
    length
  }
  guard length <= self.output.length() - self.position else { raise lzma_bad() }
  for _ in 0..<length {
    self.emit(self.history())
  }
  false
}

///|
fn lzma_properties(
  properties : Bytes,
) -> (Int32, Int32, Int32) raise ArchiveError {
  guard properties.length() == 5 && properties[0].to_int() < 225 else {
    raise Invalid(
      offset=0,
      reason="LZMA1 needs five property bytes with lc=0–8, lp=0–4 and pb=0–4",
    )
  }
  let value = properties[0].to_int()
  (value % 9, value / 9 % 5, value / 45)
}

///|
fn lzma_probabilities(
  properties : Bytes,
  limits : Limits,
) -> Int32 raise ArchiveError {
  let (lc, lp, _) = lzma_properties(properties)
  let count = 1846 + (0x300 << (lc + lp))
  ignore(
    bounded(
      count.to_uint64() * 4UL,
      limits.lzma_probability_bytes,
      "LZMA1 probability bytes",
    ),
  )
  count
}

///|
fn decode_lzma1(
  packed : Bytes,
  expected : Int32,
  properties : Bytes,
  limits : Limits,
) -> Bytes raise ArchiveError {
  guard expected >= 0 else {
    raise Invalid(offset=0, reason="negative LZMA1 output size")
  }
  ignore(
    bounded(
      expected.to_uint64(),
      limits.working_bytes,
      "LZMA1 coder output bytes",
    ),
  )
  let (lc, lp, pb) = lzma_properties(properties)
  let count = lzma_probabilities(properties, limits)
  let dict = dictionary({ codec_id: b"\x03\x01\x01", properties, })
  let dictionary = bounded(dict, limits.dictionary_bytes, "dictionary bytes").reinterpret_as_uint()
  try {
    let input = Cursor::new(packed)
    guard input.byte() == 0 else { raise lzma_bad() }
    let mut code = 0U
    for _ in 0..<4 {
      code = (code << 8) | input.byte().reinterpret_as_uint()
    }
    guard code != 0xffffffffU else { raise lzma_bad() }
    let range : LzmaInput = {
      input,
      code,
      range: 0xffffffffU,
      probabilities: FixedArray::make(count, 1024U),
    }
    let model : LzmaModel = {
      range,
      dictionary,
      output: FixedArray::make(expected, b'\x00'),
      lc,
      lp,
      pb,
      reps: FixedArray::make(4, 0U),
      state: 0,
      position: 0,
    }
    while model.position < expected {
      ignore(model.symbol(false))
    }
    if range.code != 0U || input.pos != packed.length() {
      guard model.symbol(true) else { raise lzma_bad() }
    }
    guard range.code == 0U else { raise lzma_bad() }
    input.end()
    Bytes::makei(expected, i => model.output[i])
  } catch {
    Invalid(offset~, ..) =>
      raise Codec(
        reason="truncated or unconsumed LZMA1 packed input near offset \{offset}",
      )
    error => raise error
  }
}
