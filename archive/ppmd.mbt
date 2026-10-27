// Ppmd7z scalar decoder adapted from Ppmd7Dec.c, 7-Zip 26.05.
// 2023-09-07 : Igor Pavlov : Public domain.
// Based on PPMd var.H (2001): Dmitry Shkarin : Public domain.

///|
priv struct PpmRange {
  input : Cursor
  mut code : UInt32
  mut range : UInt32
}

///|
fn PpmRange::normalize(self : PpmRange) -> Unit raise ArchiveError {
  if self.range < 0x1000000U {
    self.code = (self.code << 8) | self.input.byte().reinterpret_as_uint()
    self.range = self.range << 8
    if self.range < 0x1000000U {
      self.code = (self.code << 8) | self.input.byte().reinterpret_as_uint()
      self.range = self.range << 8
    }
  }
  guard self.range != 0U else { raise ppm_bad() }
}

///|
fn PpmRange::threshold(
  self : PpmRange,
  total : Int32,
) -> Int32 raise ArchiveError {
  guard total > 0 else { raise ppm_bad() }
  self.range = self.range / total.reinterpret_as_uint()
  guard self.range != 0U else { raise ppm_bad() }
  let count = self.code / self.range
  guard count < total.reinterpret_as_uint() else { raise ppm_bad() }
  count.reinterpret_as_int()
}

///|
fn PpmRange::decode(
  self : PpmRange,
  start : Int32,
  size : Int32,
) -> Unit raise ArchiveError {
  guard start >= 0 && size > 0 else { raise ppm_bad() }
  self.code -= start.reinterpret_as_uint() * self.range
  self.range *= size.reinterpret_as_uint()
}

///|
fn Ppm::symbol(self : Ppm, range : PpmRange) -> Int32 raise ArchiveError {
  let mask = self.mask
  let count = self.word(self.min_context)
  guard count >= 1 && count <= 256 else { raise ppm_bad() }
  if count != 1 {
    let start = self.stats(self.min_context)
    let sum = self.word(self.min_context + 2)
    let value = range.threshold(sum)
    let mut cumulative = 0
    for i in 0..<count {
      let at = start + i * 6
      let frequency = self.byte(at + 1)
      if value < cumulative + frequency {
        range.decode(cumulative, frequency)
        range.normalize()
        self.found = at
        let symbol = self.byte(at)
        if i != 0 {
          self.previous = 0
        }
        self.update(i == 0, false)
        return symbol
      }
      cumulative += frequency
    }
    for i in 0..<256 {
      mask[i] = true
    }
    for i in 0..<count {
      mask[self.byte(start + i * 6)] = false
    }
    self.previous = 0
    range.decode(cumulative, sum - cumulative)
    self.high_bits = if self.byte(self.found) < 0x40 { 0 } else { 8 }
  } else {
    let at = self.min_context + 2
    let suffix_count = self.word(self.suffix(self.min_context))
    guard suffix_count >= 1 && suffix_count <= 256 else { raise ppm_bad() }
    let frequency = self.byte(at + 1)
    guard frequency >= 1 && frequency <= 128 else { raise ppm_bad() }
    self.high_bits = if self.byte(self.found) < 0x40 { 0 } else { 8 }
    let column = self.previous +
      ((self.run >> 26) & 32) +
      self.ns_binary[suffix_count - 1] +
      ppm_bit(self.byte(at) >= 0x40) * 16 +
      self.high_bits
    let index = (frequency - 1) * 64 + column
    let probability = self.binary[index]
    let bound = (range.range >> 14) * probability.reinterpret_as_uint()
    let updated = probability - ((probability + 32) >> 7)
    if range.code < bound {
      self.binary[index] = updated + 128
      range.range = bound
      range.normalize()
      let symbol = self.byte(at)
      self.found = at
      self.previous = 1
      self.run += 1
      self.put(at + 1, frequency + ppm_bit(frequency < 128))
      self.next_context()
      return symbol
    }
    self.binary[index] = updated
    let escapes = [25, 14, 9, 7, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2, 2]
    self.initial_escape = escapes[updated >> 10]
    range.code -= bound
    range.range -= bound
    for i in 0..<256 {
      mask[i] = true
    }
    mask[self.byte(at)] = false
    self.previous = 0
  }
  let mut escapes = 0
  for ;; {
    range.normalize()
    let masked = self.word(self.min_context)
    for ;; {
      escapes += 1
      guard escapes <= 65 else { raise ppm_bad() }
      self.order_fall += 1
      let suffix = self.suffix(self.min_context)
      if suffix == 0 {
        return -1
      }
      self.min_context = suffix
      if self.word(suffix) != masked {
        break
      }
    }
    let start = self.stats(self.min_context)
    let count = self.word(self.min_context)
    let mut available = 0
    for i in 0..<count {
      let at = start + i * 6
      if mask[self.byte(at)] {
        available += self.byte(at + 1)
      }
    }
    let (see, escape) = self.escape_frequency(masked)
    let total = available + escape
    let value = range.threshold(total)
    if value < available {
      let mut cumulative = 0
      for i in 0..<count {
        let at = start + i * 6
        let symbol = self.byte(at)
        if !mask[symbol] {
          continue
        }
        let frequency = self.byte(at + 1)
        if value < cumulative + frequency {
          range.decode(cumulative, frequency)
          range.normalize()
          if see.shift < 7 {
            see.count -= 1
            if see.count == 0 {
              see.sum = (see.sum << 1) & 65535
              see.count = 3 << see.shift
              see.shift += 1
            }
          }
          self.found = at
          self.update(false, true)
          return symbol
        }
        cumulative += frequency
      }
      raise ppm_bad()
    }
    range.decode(available, total - available)
    see.sum = (see.sum + total) & 65535
    for i in 0..<count {
      mask[self.byte(start + i * 6)] = false
    }
  }
}

///|
fn ppm_properties(properties : Bytes) -> (Int32, UInt64) raise ArchiveError {
  guard properties.length() == 5 else {
    raise Invalid(offset=0, reason="PPMd7 needs five property bytes")
  }
  let order = properties[0].to_int()
  let memory = Cursor::new(properties[1:].to_owned()).u32().to_uint64()
  guard order >= 2 && order <= 64 && memory >= 2048UL && memory <= 0xffffffdbUL else {
    raise Invalid(
      offset=0,
      reason="PPMd7 order must be 2–64 and model memory 2048–4294967259 bytes",
    )
  }
  (order, memory)
}

///|
fn decode_ppmd(
  packed : Bytes,
  expected : Int32,
  properties : Bytes,
  limits : Limits,
) -> Bytes raise ArchiveError {
  guard expected >= 0 else {
    raise Invalid(offset=0, reason="negative PPMd7 output size")
  }
  // Header/auxiliary final-output quotas differ from file-data output quotas.
  // Every graph bounds the sum of all coder outputs by working_bytes.
  ignore(
    bounded(
      expected.to_uint64(),
      limits.working_bytes,
      "PPMd7 coder output bytes",
    ),
  )
  let (order, memory) = ppm_properties(properties)
  let size = bounded(memory, limits.dictionary_bytes, "dictionary bytes")
  let input = Cursor::new(packed)
  guard input.byte() == 0 else { raise ppm_bad() }
  let mut code = 0U
  for _ in 0..<4 {
    code = (code << 8) | input.byte().reinterpret_as_uint()
  }
  guard code != 0xffffffffU else { raise ppm_bad() }
  let range : PpmRange = { input, code, range: 0xffffffffU, }
  let model = Ppm::new(order, size)
  let output = FixedArray::make(expected, b'\x00')
  for i in 0..<expected {
    let symbol = model.symbol(range)
    guard symbol >= 0 else {
      raise Codec(reason="PPMd7 end marker precedes declared output size")
    }
    output[i] = symbol.to_byte()
  }
  guard range.code == 0U else {
    raise Codec(
      reason="PPMd7 range coder did not finish at declared output size",
    )
  }
  input.end()
  Bytes::makei(expected, i => output[i])
}
