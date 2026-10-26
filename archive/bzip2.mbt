///|
/// Bounded BZip2 decoding. MTF/run decoding and single-array inverse BWT are
/// adapted from Go 1.25.3 compress/bzip2, Copyright 2011 The Go Authors,
/// BSD-3-Clause (licenses/go-BSD-3-Clause.txt). Whole-node output and limits,
/// typed diagnostics and randomized-block handling are Moon7z integration.
priv struct BzipBits {
  data : Bytes
  mut pos : Int32
  mut bits : UInt64
  mut count : Int32
}

///|
fn BzipBits::read(self : BzipBits, width : Int32) -> Int32 raise ArchiveError {
  while self.count < width {
    guard self.pos < self.data.length() else {
      raise Invalid(offset=self.pos, reason="truncated BZip2 bit field")
    }
    self.bits = (self.bits << 8) | self.data[self.pos].to_uint64()
    self.pos += 1
    self.count += 8
  }
  self.count -= width
  let result = (self.bits >> self.count) & ((1UL << width) - 1UL)
  self.bits = self.bits & ((1UL << self.count) - 1UL)
  result.to_int()
}

///|
fn BzipBits::u32(self : BzipBits) -> UInt32 raise ArchiveError {
  (self.read(16).reinterpret_as_uint() << 16) |
  self.read(16).reinterpret_as_uint()
}

///|
fn BzipBits::magic(self : BzipBits) -> UInt64 raise ArchiveError {
  (self.read(24).to_uint64() << 24) | self.read(24).to_uint64()
}

///|
priv struct BzipTree {
  counts : Array[Int32]
  symbols : Array[Int32]
  maximum : Int32
}

///|
fn BzipTree::new(lengths : Array[Int32]) -> BzipTree raise ArchiveError {
  let counts = Array::make(21, 0)
  let mut maximum = 0
  for length in lengths {
    guard length >= 1 && length <= 20 else {
      raise Codec(reason="BZip2 Huffman length outside 1..20")
    }
    counts[length] += 1
    maximum = maximum.max(length)
  }
  let mut available = 1
  for length in 1..<=maximum {
    available = available * 2 - counts[length]
    guard available >= 0 else {
      raise Codec(reason="oversubscribed BZip2 Huffman tree")
    }
  }
  let symbols : Array[Int32] = []
  for length in 1..<=maximum {
    for symbol, size in lengths {
      if size == length {
        symbols.push(symbol)
      }
    }
  }
  { counts, symbols, maximum, }
}

///|
fn BzipTree::symbol(
  self : BzipTree,
  input : BzipBits,
) -> Int32 raise ArchiveError {
  let mut code = 0
  let mut first = 0
  let mut start = 0
  for length in 1..<=self.maximum {
    code = (code << 1) | input.read(1)
    let count = self.counts[length]
    if code >= first && code - first < count {
      return self.symbols[start + code - first]
    }
    start += count
    first = (first + count) << 1
  }
  raise Codec(reason="invalid BZip2 Huffman symbol")
}

///|
fn bzip_mtf(values : Array[Int32], index : Int32) -> Int32 {
  let value = values[index]
  for i = index; i > 0; i = i - 1 {
    values[i] = values[i - 1]
  }
  values[0] = value
  value
}

///|
let bzip_crc_table : Array[UInt32] = Array::makei(256, i => {
  let mut crc = i.reinterpret_as_uint() << 24
  for _ in 0..<8 {
    crc = (crc << 1) ^
      (if (crc & 0x80000000U) != 0U { 0x04c11db7U } else { 0U })
  }
  crc
})

///|
fn bzip_emit(
  output : Array[Byte],
  value : Int32,
  remaining : Int32,
  crc : UInt32,
) -> UInt32 raise ArchiveError {
  guard output.length() < remaining else {
    raise Codec(reason="BZip2 RLE expansion exceeds declared output")
  }
  output.push(value.to_byte())
  (crc << 8) ^ bzip_crc_table[((crc >> 24).reinterpret_as_int() ^ value) & 255]
}

///|
fn decode_bzip_block(
  input : BzipBits,
  block_size : Int32,
  output : Array[Byte],
  size : Int32,
) -> UInt32 raise ArchiveError {
  let expected_crc = input.u32()
  let randomized = input.read(1) != 0
  let original = input.read(24)
  let groups = input.read(16)
  let symbols : Array[Int32] = []
  for group in 0..<16 {
    if (groups & (1 << (15 - group))) != 0 {
      let used = input.read(16)
      for i in 0..<16 {
        if (used & (1 << (15 - i))) != 0 {
          symbols.push(group * 16 + i)
        }
      }
    }
  }
  guard !symbols.is_empty() else {
    raise Codec(reason="BZip2 block has no symbols")
  }
  let alphabet = symbols.length() + 2
  let tree_count = input.read(3)
  guard tree_count >= 2 && tree_count <= 6 else {
    raise Codec(reason="BZip2 tree count outside 2..6")
  }
  let selector_count = input.read(15)
  guard selector_count > 0 else {
    raise Codec(reason="BZip2 block has no tree selectors")
  }
  let mtf_trees = Array::makei(tree_count, i => i)
  let selectors : Array[Int32] = []
  for _ in 0..<selector_count {
    let mut index = 0
    while input.read(1) != 0 {
      index += 1
      guard index < tree_count else {
        raise Codec(reason="BZip2 selector exceeds tree count")
      }
    }
    selectors.push(bzip_mtf(mtf_trees, index))
  }
  let trees : Array[BzipTree] = []
  for _ in 0..<tree_count {
    let mut length = input.read(5)
    let lengths : Array[Int32] = []
    for _ in 0..<alphabet {
      for ;; {
        guard length >= 1 && length <= 20 else {
          raise Codec(reason="invalid BZip2 delta code length")
        }
        if input.read(1) == 0 {
          break
        }
        length += if input.read(1) == 0 { 1 } else { -1 }
      }
      lengths.push(length)
    }
    trees.push(BzipTree::new(lengths))
  }
  let data : Array[UInt32] = []
  let counts = Array::make(256, 0)
  let mut used = 0
  let mut repeat = 0
  let mut power = 1
  for ;; {
    guard used / 50 < selectors.length() else {
      raise Codec(reason="BZip2 has insufficient tree selectors")
    }
    let symbol = trees[selectors[used / 50]].symbol(input)
    used += 1
    if symbol < 2 {
      let extra = power * (symbol + 1)
      guard extra <= block_size - data.length() - repeat else {
        raise Codec(reason="BZip2 run exceeds block size")
      }
      repeat += extra
      power *= 2
      continue
    }
    for _ in 0..<repeat {
      let value = symbols[0]
      data.push(value.reinterpret_as_uint())
      counts[value] += 1
    }
    repeat = 0
    power = 1
    if symbol == alphabet - 1 {
      break
    }
    guard symbol > 1 && symbol < alphabet - 1 else {
      raise Codec(reason="invalid BZip2 MTF symbol")
    }
    guard data.length() < block_size else {
      raise Codec(reason="BZip2 data exceeds block size")
    }
    let value = bzip_mtf(symbols, symbol - 1)
    data.push(value.reinterpret_as_uint())
    counts[value] += 1
  }
  guard original < data.length() else {
    raise Codec(reason="BZip2 original pointer outside block")
  }
  let mut total = 0
  for i in 0..<256 {
    let count = counts[i]
    counts[i] = total
    total += count
  }
  for i in 0..<data.length() {
    let value = (data[i] & 255U).reinterpret_as_int()
    let destination = counts[value]
    data[destination] = data[destination] | (i.reinterpret_as_uint() << 8)
    counts[value] += 1
  }
  let mut position = (data[original] >> 8).reinterpret_as_int()
  let mut previous = -1
  let mut equal = 0
  let mut crc = 0xffffffffU
  let mut random_left = 0
  let mut random_index = 0
  for _ in 0..<data.length() {
    let word = data[position]
    position = (word >> 8).reinterpret_as_int()
    let mut value = (word & 255U).reinterpret_as_int()
    if randomized {
      if random_left == 0 {
        random_left = bzip_random[random_index]
        random_index = (random_index + 1) % 512
      }
      random_left -= 1
      if random_left == 1 {
        value = value ^ 1
      }
    }
    if equal == 4 {
      guard value <= size - output.length() else {
        raise Codec(reason="BZip2 repeated run exceeds declared output")
      }
      for _ in 0..<value {
        crc = bzip_emit(output, previous, size, crc)
      }
      previous = -1
      equal = 0
    } else {
      crc = bzip_emit(output, value, size, crc)
      equal = if previous == value { equal + 1 } else { 1 }
      previous = value
    }
  }
  guard equal != 4 else { raise Codec(reason="truncated BZip2 RLE run count") }
  crc = crc ^ 0xffffffffU
  guard crc == expected_crc else { raise Checksum(scope="BZip2 block") }
  crc
}

///|
fn decode_bzip2(
  packed : Bytes,
  size : Int32,
  dictionary_bytes : Int32,
) -> Bytes raise ArchiveError {
  let input : BzipBits = { data: packed, pos: 0, bits: 0UL, count: 0, }
  let output : Array[Byte] = Array(capacity=size)
  guard !packed.is_empty() else { raise Codec(reason="missing BZip2 stream") }
  while input.pos < packed.length() {
    guard input.read(24) == 0x425a68 else {
      raise Codec(reason="expected BZip2 BZh header; trailing data is refused")
    }
    let level = input.read(8) - 48
    guard level >= 1 && level <= 9 else {
      raise Codec(reason="BZip2 block level outside 1..9")
    }
    let block_size = level * 100000
    ignore(
      bounded(block_size.to_uint64(), dictionary_bytes, "BZip2 block bytes"),
    )
    let mut combined = 0U
    for ;; {
      let magic = input.magic()
      if magic == 0x177245385090UL {
        guard input.u32() == combined else {
          raise Checksum(scope="BZip2 stream")
        }
        break
      }
      guard magic == 0x314159265359UL else {
        raise Codec(reason="invalid BZip2 block marker")
      }
      let crc = decode_bzip_block(input, block_size, output, size)
      combined = ((combined << 1) | (combined >> 31)) ^ crc
    }
    input.bits = 0UL
    input.count = 0
  }
  guard output.length() == size else {
    raise Codec(reason="BZip2 output differs from declared size")
  }
  Bytes::from_array(output)
}
