// Portable bounded adaptation of Ppmd7.c, 7-Zip 26.05.
// 2023-09-07 : Igor Pavlov : Public domain.
// Based on PPMd var.H (2001): Dmitry Shkarin : Public domain.

///|
fn ppm_bit(value : Bool) -> Int32 {
  if value {
    1
  } else {
    0
  }
}

///|
fn Ppm::successors(self : Ppm) -> Int32 raise ArchiveError {
  let mut context = self.min_context
  let branch = self.pointer(self.found + 2)
  let states : Array[Int32] = []
  if self.order_fall != 0 {
    states.push(self.found)
  }
  while self.suffix(context) != 0 {
    guard states.length() <= self.order else { raise ppm_bad() }
    context = self.suffix(context)
    let at = self.find(context, self.byte(self.found))
    let successor = self.pointer(at + 2)
    if successor != branch {
      context = successor
      if states.is_empty() {
        return context
      }
      break
    }
    states.push(at)
  }
  let symbol = self.byte(branch)
  let frequency = if self.word(context) == 1 {
    self.byte(context + 3)
  } else {
    let at = self.find(context, symbol)
    let cf = self.byte(at + 1) - 1
    let s0 = self.word(context + 2) - self.word(context) - cf
    guard s0 > 0 else { raise ppm_bad() }
    1 +
    (if 2 * cf <= s0 {
      ppm_bit(5 * cf > s0)
    } else {
      (2 * cf + s0 - 1) / (2 * s0) + 1
    })
  }
  guard !states.is_empty() && states.length() <= 64 else { raise ppm_bad() }
  for i = states.length() - 1; i >= 0; i = i - 1 {
    let next = self.context()
    if next == 0 {
      return 0
    }
    self.put_word(next, 1)
    self.put(next + 2, symbol)
    self.put(next + 3, frequency)
    self.set_pointer(next + 4, branch + 1)
    self.set_pointer(next + 8, context)
    self.set_pointer(states[i] + 2, next)
    context = next
  }
  context
}

///|
fn Ppm::update_model(self : Ppm) -> Unit raise ArchiveError {
  if self.byte(self.found + 1) < 31 && self.suffix(self.min_context) != 0 {
    let context = self.suffix(self.min_context)
    if self.word(context) == 1 {
      if self.byte(context + 3) < 32 {
        self.put(context + 3, self.byte(context + 3) + 1)
      }
    } else {
      let start = self.stats(context)
      let mut at = self.find(context, self.byte(self.found))
      if at != start && self.byte(at + 1) >= self.byte(at - 5) {
        self.swap(at, at - 6)
        at -= 6
      }
      if self.byte(at + 1) < 115 {
        self.put(at + 1, self.byte(at + 1) + 2)
        self.put_word(context + 2, self.word(context + 2) + 2)
      }
    }
  }
  if self.order_fall == 0 {
    let next = self.successors()
    self.min_context = next
    self.max_context = next
    if next == 0 {
      self.restart()
      return
    }
    self.set_pointer(self.found + 2, next)
    return
  }
  self.put(self.text, self.byte(self.found))
  self.text += 1
  if self.text >= self.units_start {
    self.restart()
    return
  }
  let mut maximum = self.text
  let mut minimum = self.pointer(self.found + 2)
  if minimum != 0 {
    if minimum <= maximum {
      minimum = self.successors()
      if minimum == 0 {
        self.restart()
        return
      }
    }
    self.order_fall -= 1
    if self.order_fall == 0 {
      maximum = minimum
      self.text -= ppm_bit(self.max_context != self.min_context)
    }
  } else {
    self.set_pointer(self.found + 2, maximum)
    minimum = self.min_context
  }
  let original = self.min_context
  let mut context = self.max_context
  self.min_context = minimum
  self.max_context = minimum
  if context == original {
    return
  }
  let ns = self.word(original)
  let s0 = self.word(original + 2) - ns - (self.byte(self.found + 1) - 1)
  let mut visits = 0
  while context != original {
    visits += 1
    guard visits <= 65 else { raise ppm_bad() }
    let count = self.word(context)
    guard count >= 1 && count < 256 else { raise ppm_bad() }
    let mut sum = 0
    if count != 1 {
      if (count & 1) == 0 {
        let old_units = count >> 1
        let i = self.indexes[old_units - 1]
        if i != self.indexes[old_units] {
          let next = self.allocate(i + 1)
          if next == 0 {
            self.restart()
            return
          }
          let old = self.stats(context)
          self.copy(next, old, old_units * 12)
          self.insert(old, i)
          self.set_pointer(context + 4, next)
        }
      }
      sum = self.word(context + 2)
      sum += ppm_bit(2 * count < ns) +
        2 * ppm_bit(4 * count <= ns && sum <= 8 * count)
    } else {
      let at = self.allocate(0)
      if at == 0 {
        self.restart()
        return
      }
      let mut frequency = self.byte(context + 3)
      self.copy(at, context + 2, 6)
      self.set_pointer(context + 4, at)
      frequency = if frequency < 30 { frequency << 1 } else { 120 }
      self.put(at + 1, frequency)
      sum = frequency + self.initial_escape + ppm_bit(ns > 3)
    }
    let at = self.pointer(context + 4) + count * 6
    let mut cf = 2 * (sum + 6) * self.byte(self.found + 1)
    let sf = s0 + sum
    self.put(at, self.byte(self.found))
    self.put_word(context, count + 1)
    self.set_pointer(at + 2, maximum)
    if cf < 6 * sf {
      cf = 1 + ppm_bit(cf > sf) + ppm_bit(cf >= 4 * sf)
      sum += 3
    } else {
      cf = 4 +
        ppm_bit(cf >= 9 * sf) +
        ppm_bit(cf >= 12 * sf) +
        ppm_bit(cf >= 15 * sf)
      sum += cf
    }
    self.put_word(context + 2, sum)
    self.put(at + 1, cf)
    context = self.suffix(context)
  }
}

///|
fn Ppm::rescale(self : Ppm) -> Unit raise ArchiveError {
  let context = self.min_context
  let start = self.stats(context)
  let mut at = self.found
  guard at >= start && (at - start) % 6 == 0 else { raise ppm_bad() }
  while at != start {
    self.swap(at, at - 6)
    at -= 6
  }
  let mut sum = self.byte(at + 1)
  let mut escape = self.word(context + 2) - sum
  let adder = ppm_bit(self.order_fall != 0)
  sum = (sum + 4 + adder) >> 1
  self.put(at + 1, sum)
  let count = self.word(context)
  guard count > 1 && count <= 256 else { raise ppm_bad() }
  for i in 1..<count {
    at = start + i * 6
    let old = self.byte(at + 1)
    escape -= old
    let frequency = (old + adder) >> 1
    sum += frequency
    self.put(at + 1, frequency)
    while at != start && frequency > self.byte(at - 5) {
      self.swap(at, at - 6)
      at -= 6
    }
  }
  let mut remaining = count
  while remaining > 1 && self.byte(start + (remaining - 1) * 6 + 1) == 0 {
    remaining -= 1
  }
  if remaining != count {
    escape += count - remaining
    self.put_word(context, remaining)
    let old_units = (count + 1) >> 1
    if remaining == 1 {
      let mut frequency = self.byte(start + 1)
      for ;; {
        escape = escape >> 1
        frequency = (frequency + 1) >> 1
        if escape <= 1 {
          break
        }
      }
      self.copy(context + 2, start, 6)
      self.put(context + 3, frequency)
      self.found = context + 2
      self.insert(start, self.indexes[old_units - 1])
      return
    }
    let new_units = (remaining + 1) >> 1
    let i0 = self.indexes[old_units - 1]
    let i1 = self.indexes[new_units - 1]
    if old_units != new_units && i0 != i1 {
      if self.free[i1] != 0 {
        let next = self.remove(i1)
        self.set_pointer(context + 4, next)
        self.copy(next, start, new_units * 12)
        self.insert(start, i0)
      } else {
        self.split(start, i0, i1)
      }
    }
  }
  self.put_word(context + 2, sum + escape - (escape >> 1))
  self.found = self.stats(context)
}

///|
fn Ppm::next_context(self : Ppm) -> Unit raise ArchiveError {
  let next = self.pointer(self.found + 2)
  if self.order_fall == 0 && next > self.text {
    self.min_context = next
    self.max_context = next
  } else {
    self.update_model()
  }
}

///|
fn Ppm::update(
  self : Ppm,
  first : Bool,
  escaped : Bool,
) -> Unit raise ArchiveError {
  let at = self.found
  let old = self.byte(at + 1)
  let sum = self.word(self.min_context + 2)
  self.put_word(self.min_context + 2, sum + 4)
  self.put(at + 1, old + 4)
  if escaped {
    self.run = self.initial_run
    if old + 4 > 124 {
      self.rescale()
    }
    self.update_model()
  } else {
    if first {
      self.previous = ppm_bit(2 * old > sum)
      self.run += self.previous
      if old + 4 > 124 {
        self.rescale()
      }
    } else if old + 4 > self.byte(at - 5) {
      self.swap(at, at - 6)
      self.found -= 6
      if old + 4 > 124 {
        self.rescale()
      }
    }
    self.next_context()
  }
}

///|
fn Ppm::escape_frequency(
  self : Ppm,
  masked : Int32,
) -> (PpmSee, Int32) raise ArchiveError {
  let context = self.min_context
  let count = self.word(context)
  if count == 256 {
    return (self.see[400], 1)
  }
  let available = count - masked
  guard available > 0 && available <= 256 else { raise ppm_bad() }
  let column = ppm_bit(available < self.word(self.suffix(context)) - count) +
    2 * ppm_bit(self.word(context + 2) < 11 * count) +
    4 * ppm_bit(masked > available) +
    self.high_bits
  let index = self.ns_index[available - 1] * 16 + column
  guard index >= 0 && index < 400 else { raise ppm_bad() }
  let see = self.see[index]
  let value = see.sum >> see.shift
  see.sum = (see.sum - value) & 65535
  (see, if value > 0 { value } else { 1 })
}
