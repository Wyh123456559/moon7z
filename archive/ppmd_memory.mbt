// Bounded offset-arena adaptation of Ppmd7.c, 7-Zip 26.05.
// 2023-09-07 : Igor Pavlov : Public domain.
// Based on PPMd var.H (2001): Dmitry Shkarin : Public domain.

///|
priv struct PpmSee {
  mut sum : Int32
  mut shift : Int32
  mut count : Int32
}

///|
priv struct Ppm {
  arena : FixedArray[Byte]
  size : Int32
  align : Int32
  order : Int32
  free : Array[Int32]
  units : Array[Int32]
  indexes : Array[Int32]
  ns_index : Array[Int32]
  ns_binary : Array[Int32]
  binary : Array[Int32]
  mask : FixedArray[Bool]
  see : Array[PpmSee]
  mut text : Int32
  mut units_start : Int32
  mut low : Int32
  mut high : Int32
  mut glue : Int32
  mut min_context : Int32
  mut max_context : Int32
  mut found : Int32
  mut order_fall : Int32
  mut run : Int32
  mut initial_run : Int32
  mut previous : Int32
  mut initial_escape : Int32
  mut high_bits : Int32
  mut _restarts : Int32
  mut _gluing : Int32
}

///|
fn ppm_bad() -> ArchiveError {
  Codec(reason="invalid PPMd7 model or compressed data")
}

///|
fn Ppm::byte(self : Ppm, at : Int32) -> Int32 raise ArchiveError {
  guard at >= 0 && at < self.arena.length() else { raise ppm_bad() }
  self.arena[at].to_int()
}

///|
fn Ppm::put(self : Ppm, at : Int32, value : Int32) -> Unit raise ArchiveError {
  guard at >= 0 && at < self.arena.length() else { raise ppm_bad() }
  self.arena[at] = value.to_byte()
}

///|
fn Ppm::word(self : Ppm, at : Int32) -> Int32 raise ArchiveError {
  self.byte(at) | (self.byte(at + 1) << 8)
}

///|
fn Ppm::put_word(
  self : Ppm,
  at : Int32,
  value : Int32,
) -> Unit raise ArchiveError {
  self.put(at, value)
  self.put(at + 1, value >> 8)
}

///|
fn Ppm::pointer(self : Ppm, at : Int32) -> Int32 raise ArchiveError {
  let value = self.word(at).reinterpret_as_uint() |
    (self.word(at + 2).reinterpret_as_uint() << 16)
  guard value <= self.arena.length().reinterpret_as_uint() else {
    raise ppm_bad()
  }
  value.reinterpret_as_int()
}

///|
fn Ppm::set_pointer(
  self : Ppm,
  at : Int32,
  value : Int32,
) -> Unit raise ArchiveError {
  guard value >= 0 && value <= self.arena.length() else { raise ppm_bad() }
  self.put_word(at, value)
  self.put_word(at + 2, value >> 16)
}

///|
fn Ppm::copy(
  self : Ppm,
  dest : Int32,
  src : Int32,
  length : Int32,
) -> Unit raise ArchiveError {
  guard length >= 0 &&
    src >= 0 &&
    dest >= 0 &&
    length <= self.arena.length() - src &&
    length <= self.arena.length() - dest else {
    raise ppm_bad()
  }
  if dest > src {
    for i = length - 1; i >= 0; i = i - 1 {
      self.arena[dest + i] = self.arena[src + i]
    }
  } else {
    for i in 0..<length {
      self.arena[dest + i] = self.arena[src + i]
    }
  }
}

///|
fn Ppm::swap(self : Ppm, a : Int32, b : Int32) -> Unit raise ArchiveError {
  for i in 0..<6 {
    let v = self.byte(a + i)
    self.put(a + i, self.byte(b + i))
    self.put(b + i, v)
  }
}

///|
fn Ppm::stats(self : Ppm, context : Int32) -> Int32 raise ArchiveError {
  let n = self.word(context)
  guard n >= 1 && n <= 256 else { raise ppm_bad() }
  if n == 1 {
    context + 2
  } else {
    self.pointer(context + 4)
  }
}

///|
fn Ppm::suffix(self : Ppm, context : Int32) -> Int32 raise ArchiveError {
  self.pointer(context + 8)
}

///|
fn Ppm::find(
  self : Ppm,
  context : Int32,
  symbol : Int32,
) -> Int32 raise ArchiveError {
  let start = self.stats(context)
  for i in 0..<self.word(context) {
    let at = start + 6 * i
    if self.byte(at) == symbol {
      return at
    }
  }
  raise ppm_bad()
}

///|
fn Ppm::insert(
  self : Ppm,
  at : Int32,
  index : Int32,
) -> Unit raise ArchiveError {
  guard index >= 0 && index < 38 && at > 0 else { raise ppm_bad() }
  self.set_pointer(at, self.free[index])
  self.free[index] = at
}

///|
fn Ppm::remove(self : Ppm, index : Int32) -> Int32 raise ArchiveError {
  let at = self.free[index]
  guard at > 0 else { raise ppm_bad() }
  self.free[index] = self.pointer(at)
  at
}

///|
fn Ppm::split(
  self : Ppm,
  at : Int32,
  old_index : Int32,
  new_index : Int32,
) -> Unit raise ArchiveError {
  let count = self.units[old_index] - self.units[new_index]
  guard count > 0 && count <= 128 else { raise ppm_bad() }
  let start = at + self.units[new_index] * 12
  let mut i = self.indexes[count - 1]
  if self.units[i] != count {
    i -= 1
    let k = self.units[i]
    self.insert(start + k * 12, count - k - 1)
  }
  self.insert(start, i)
}

///|
fn Ppm::glue_blocks(self : Ppm) -> Unit raise ArchiveError {
  self._gluing += 1
  self.glue = 255
  if self.low != self.high {
    self.put_word(self.low, 1)
  }
  let mut head = 0
  let mut visits = self.size / 12 + 1
  for i in 0..<38 {
    let mut next = self.free[i]
    self.free[i] = 0
    while next != 0 {
      visits -= 1
      guard visits >= 0 else { raise ppm_bad() }
      let at = next
      next = self.pointer(at)
      self.put_word(at, 0)
      self.put_word(at + 2, self.units[i])
      self.set_pointer(at + 4, head)
      head = at
    }
  }
  let mut current = head
  let mut previous = 0
  visits = self.size / 12 + 1
  while current != 0 {
    visits -= 1
    guard visits >= 0 else { raise ppm_bad() }
    let at = current
    let mut count = self.word(at + 2)
    current = self.pointer(at + 4)
    if count == 0 {
      if previous == 0 {
        head = current
      } else {
        self.set_pointer(previous + 4, current)
      }
      continue
    }
    previous = at
    for ;; {
      let next = at + count * 12
      let combined = count + self.word(next + 2)
      if self.word(next) != 0 || combined >= 65536 {
        break
      }
      guard combined > count else { raise ppm_bad() }
      count = combined
      self.put_word(at + 2, count)
      self.put_word(next + 2, 0)
    }
  }
  current = head
  while current != 0 {
    let mut at = current
    let mut count = self.word(at + 2)
    current = self.pointer(at + 4)
    if count == 0 {
      continue
    }
    while count > 128 {
      self.insert(at, 37)
      count -= 128
      at += 128 * 12
    }
    let mut i = self.indexes[count - 1]
    if self.units[i] != count {
      i -= 1
      let k = self.units[i]
      self.insert(at + k * 12, count - k - 1)
    }
    self.insert(at, i)
  }
}

///|
fn Ppm::rare(self : Ppm, index : Int32) -> Int32 raise ArchiveError {
  if self.glue == 0 {
    self.glue_blocks()
    if self.free[index] != 0 {
      return self.remove(index)
    }
  }
  for i in (index + 1)..<38 {
    if self.free[i] != 0 {
      let at = self.remove(i)
      self.split(at, i, index)
      return at
    }
  }
  self.glue -= 1
  let length = self.units[index] * 12
  if self.units_start - self.text <= length {
    return 0
  }
  self.units_start -= length
  self.units_start
}

///|
fn Ppm::allocate(self : Ppm, index : Int32) -> Int32 raise ArchiveError {
  guard index >= 0 && index < 38 else { raise ppm_bad() }
  if self.free[index] != 0 {
    return self.remove(index)
  }
  let length = self.units[index] * 12
  if self.high - self.low >= length {
    let at = self.low
    self.low += length
    return at
  }
  self.rare(index)
}

///|
fn Ppm::context(self : Ppm) -> Int32 raise ArchiveError {
  if self.high != self.low {
    self.high -= 12
    self.high
  } else if self.free[0] != 0 {
    self.remove(0)
  } else {
    self.rare(0)
  }
}

///|
fn Ppm::restart(self : Ppm) -> Unit raise ArchiveError {
  self._restarts += 1
  self.free.fill(0)
  self.text = self.align
  self.high = self.align + self.size
  self.low = self.high - self.size / 8 / 12 * 7 * 12
  self.units_start = self.low
  self.glue = 0
  self.order_fall = self.order
  self.initial_run = -(if self.order < 12 { self.order } else { 12 }) - 1
  self.run = self.initial_run
  self.previous = 0
  self.high -= 12
  let root = self.high
  let states = self.low
  self.low += 1536
  self.min_context = root
  self.max_context = root
  self.found = states
  self.put_word(root, 256)
  self.put_word(root + 2, 257)
  self.set_pointer(root + 4, states)
  self.set_pointer(root + 8, 0)
  for i in 0..<256 {
    self.put(states + i * 6, i)
    self.put(states + i * 6 + 1, 1)
    self.set_pointer(states + i * 6 + 2, 0)
  }
  let initial = [0x3cdd, 0x1f3f, 0x59bf, 0x48f3, 0x64a1, 0x5abc, 0x6632, 0x6051]
  for i in 0..<128 {
    for k in 0..<64 {
      self.binary[i * 64 + k] = 16384 - initial[k % 8] / (i + 2)
    }
  }
  for i in 0..<400 {
    self.see[i].sum = (5 * (i / 16) + 10) << 3
    self.see[i].shift = 3
    self.see[i].count = 4
  }
  self.see[400].sum = 0
  self.see[400].shift = 7
  self.see[400].count = 64
}

///|
fn Ppm::new(order : Int32, size : Int32) -> Ppm raise ArchiveError {
  let units = Array::make(38, 0)
  let indexes = Array::make(128, 0)
  let mut k = 0
  for i in 0..<38 {
    let step = if i >= 12 { 4 } else { (i >> 2) + 1 }
    for _ in 0..<step {
      indexes[k] = i
      k += 1
    }
    units[i] = k
  }
  let ns_index = Array::make(256, 0)
  let mut n = 3
  k = 1
  for i in 0..<256 {
    if i < 3 {
      ns_index[i] = i
      continue
    }
    ns_index[i] = n
    k -= 1
    if k == 0 {
      n += 1
      k = n - 2
    }
  }
  let self : Ppm = {
    arena: FixedArray::make(size + ((4 - size) & 3), b'\x00'),
    size,
    align: (4 - size) & 3,
    order,
    free: Array::make(38, 0),
    units,
    indexes,
    ns_index,
    ns_binary: Array::makei(256, i => {
      if i < 2 {
        i * 2
      } else if i < 11 {
        4
      } else {
        6
      }
    }),
    binary: Array::make(128 * 64, 0),
    mask: FixedArray::make(256, true),
    see: Array::makei(401, _ => { sum: 0, shift: 0, count: 0, }),
    text: 0,
    units_start: 0,
    low: 0,
    high: 0,
    glue: 0,
    min_context: 0,
    max_context: 0,
    found: 0,
    order_fall: 0,
    run: 0,
    initial_run: 0,
    previous: 0,
    initial_escape: 0,
    high_bits: 0,
    _restarts: 0,
    _gluing: 0,
  }
  self.restart()
  self
}
