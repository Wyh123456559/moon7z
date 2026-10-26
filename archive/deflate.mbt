///|
/// RFC 1951 bit packing: numeric fields are LSB-first, Huffman codes MSB-first.
priv struct DeflateBits {
  data : Bytes
  mut pos : Int32
  mut bits : UInt32
  mut count : Int32
}

///|
fn DeflateBits::read(
  self : DeflateBits,
  width : Int32,
) -> Int32 raise ArchiveError {
  while self.count < width {
    guard self.pos < self.data.length() else {
      raise Invalid(offset=self.pos, reason="truncated DEFLATE bit field")
    }
    self.bits = self.bits | (self.data[self.pos].to_uint() << self.count)
    self.pos += 1
    self.count += 8
  }
  let value = self.bits & ((1U << width) - 1U)
  self.bits = self.bits >> width
  self.count -= width
  value.reinterpret_as_int()
}

///|
priv struct DeflateTree {
  counts : Array[Int32]
  symbols : Array[Int32]
  maximum : Int32
}

///|
fn DeflateTree::new(
  lengths : Array[Int32],
  code_lengths~ : Bool = false,
) -> DeflateTree raise ArchiveError {
  let counts = Array::make(16, 0)
  let mut maximum = 0
  for length in lengths {
    guard length >= 0 && length <= 15 else {
      raise Codec(reason="invalid DEFLATE code length")
    }
    if length > 0 {
      counts[length] += 1
      maximum = maximum.max(length)
    }
  }
  let mut available = 1
  for length in 1..<=15 {
    available = available * 2 - counts[length]
    guard available >= 0 else {
      raise Codec(reason="oversubscribed DEFLATE Huffman tree")
    }
  }
  guard available == 0 || (!code_lengths && maximum <= 1) else {
    raise Codec(reason="incomplete DEFLATE Huffman tree")
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
fn DeflateTree::symbol(
  self : DeflateTree,
  input : DeflateBits,
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
  raise Codec(reason="invalid DEFLATE Huffman symbol")
}

///|
fn deflate_trees(
  input : DeflateBits,
  dynamic~ : Bool,
) -> (DeflateTree, DeflateTree) raise ArchiveError {
  if !dynamic {
    return (
      DeflateTree::new(
        Array::makei(288, i => {
          if i < 144 {
            8
          } else if i < 256 {
            9
          } else if i < 280 {
            7
          } else {
            8
          }
        }),
      ),
      DeflateTree::new(Array::make(32, 5)),
    )
  }
  let literals = input.read(5) + 257
  let distances = input.read(5) + 1
  let codes = input.read(4) + 4
  guard literals <= 286 else {
    raise Codec(reason="reserved DEFLATE literal count")
  }
  let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
  let lengths = Array::make(19, 0)
  for i in 0..<codes {
    lengths[order[i]] = input.read(3)
  }
  let tree = DeflateTree::new(lengths, code_lengths=true)
  let result : Array[Int32] = []
  let total = literals + distances
  while result.length() < total {
    let symbol = tree.symbol(input)
    if symbol < 16 {
      result.push(symbol)
      continue
    }
    let (value, count) = match symbol {
      16 => {
        guard !result.is_empty() else {
          raise Codec(reason="DEFLATE repeat has no previous length")
        }
        (result[result.length() - 1], input.read(2) + 3)
      }
      17 => (0, input.read(3) + 3)
      18 => (0, input.read(7) + 11)
      _ => raise Codec(reason="invalid DEFLATE length repeat")
    }
    guard count <= total - result.length() else {
      raise Codec(reason="DEFLATE code-length repeat exceeds alphabet")
    }
    for _ in 0..<count {
      result.push(value)
    }
  }
  guard result[256] != 0 else {
    raise Codec(reason="DEFLATE literal tree has no end marker")
  }
  (
    DeflateTree::new(result[:literals].to_owned()),
    DeflateTree::new(result[literals:].to_owned()),
  )
}

///|
/// Bounded raw DEFLATE for the 7z 04 01 08 method; no ZIP/zlib/gzip wrapper.
fn decode_deflate(packed : Bytes, size : Int32) -> Bytes raise ArchiveError {
  let input : DeflateBits = { data: packed, pos: 0, bits: 0U, count: 0, }
  let output : Array[Byte] = Array(capacity=size)
  let length_base = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67,
    83, 99, 115, 131, 163, 195, 227, 258,
  ]
  let length_extra = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5,
    5, 5, 0,
  ]
  let distance_base = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
    1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
  ]
  let distance_extra = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11,
    11, 12, 12, 13, 13,
  ]
  for ;; {
    let last_block = input.read(1) == 1
    let kind = input.read(2)
    if kind == 0 {
      // read() leaves fewer than eight buffered bits, all belonging to padding.
      input.bits = 0U
      input.count = 0
      let length = input.read(16)
      guard (length ^ input.read(16)) == 65535 else {
        raise Codec(reason="DEFLATE stored length complement mismatch")
      }
      guard length <= size - output.length() else {
        raise Codec(reason="DEFLATE stored block exceeds declared output")
      }
      for _ in 0..<length {
        output.push(input.read(8).to_byte())
      }
    } else if kind == 1 || kind == 2 {
      let (literals, distances) = deflate_trees(input, dynamic=kind == 2)
      for ;; {
        let symbol = literals.symbol(input)
        if symbol == 256 {
          break
        }
        if symbol < 256 {
          guard output.length() < size else {
            raise Codec(reason="DEFLATE literal exceeds declared output")
          }
          output.push(symbol.to_byte())
          continue
        }
        guard symbol <= 285 else {
          raise Codec(reason="reserved DEFLATE length symbol")
        }
        let index = symbol - 257
        let length = length_base[index] + input.read(length_extra[index])
        let distance_symbol = distances.symbol(input)
        guard distance_symbol < 30 else {
          raise Codec(reason="reserved DEFLATE distance symbol")
        }
        let distance = distance_base[distance_symbol] +
          input.read(distance_extra[distance_symbol])
        guard distance <= output.length() else {
          raise Codec(reason="DEFLATE distance precedes available history")
        }
        guard length <= size - output.length() else {
          raise Codec(reason="DEFLATE match exceeds declared output")
        }
        for _ in 0..<length {
          output.push(output[output.length() - distance])
        }
      }
    } else {
      raise Codec(reason="reserved DEFLATE block type")
    }
    if last_block {
      break
    }
  }
  guard input.pos == packed.length() else {
    raise Invalid(
      offset=input.pos,
      reason="trailing bytes after DEFLATE stream",
    )
  }
  guard output.length() == size else {
    raise Codec(reason="DEFLATE output differs from declared size")
  }
  Bytes::from_array(output)
}
