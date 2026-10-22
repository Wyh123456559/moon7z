///|
priv struct Cursor {
  data : Bytes
  mut pos : Int32
}

///|
fn Cursor::new(data : Bytes) -> Cursor {
  { data, pos: 0, }
}

///|
fn Cursor::byte(self : Cursor) -> Int32 raise ArchiveError {
  guard self.pos < self.data.length() else {
    raise Invalid(offset=self.pos, reason="truncated header or stream")
  }
  let value = self.data[self.pos].to_int()
  self.pos += 1
  value
}

///|
fn Cursor::take(self : Cursor, count : Int32) -> Bytes raise ArchiveError {
  guard count >= 0 && count <= self.data.length() - self.pos else {
    raise Invalid(offset=self.pos, reason="length exceeds available bytes")
  }
  let value = self.data[self.pos:self.pos + count].to_owned()
  self.pos += count
  value
}

///|
fn Cursor::expect(self : Cursor, wanted : Int32) -> Unit raise ArchiveError {
  let actual = self.byte()
  guard actual == wanted else {
    raise Invalid(
      offset=self.pos - 1,
      reason="expected property \{wanted}, found \{actual}",
    )
  }
}

///|
fn Cursor::end(self : Cursor) -> Unit raise ArchiveError {
  guard self.pos == self.data.length() else {
    raise Invalid(offset=self.pos, reason="unused bytes in bounded property")
  }
}

///|
fn Cursor::u32(self : Cursor) -> UInt32 raise ArchiveError {
  let mut value = 0U
  for shift in 0..<4 {
    value = value | (self.byte().reinterpret_as_uint() << (shift * 8))
  }
  value
}

///|
fn Cursor::u64(self : Cursor) -> UInt64 raise ArchiveError {
  let mut value = 0UL
  for shift in 0..<8 {
    value = value | (self.byte().to_uint64() << (shift * 8))
  }
  value
}

///|
/// 7z integers encode the number of trailing bytes in the leading bits.
fn Cursor::number(self : Cursor) -> UInt64 raise ArchiveError {
  let first = self.byte()
  let mut mask = 0x80
  let mut value = 0UL
  for i in 0..<8 {
    if (first & mask) == 0 {
      return value | ((first & (mask - 1)).to_uint64() << (8 * i))
    }
    value = value | (self.byte().to_uint64() << (8 * i))
    mask = mask >> 1
  }
  value
}

///|
fn bounded(
  value : UInt64,
  maximum : Int32,
  resource : String,
) -> Int32 raise ArchiveError {
  guard maximum >= 0 && value <= maximum.to_uint64() else {
    raise Limit(resource~, maximum~)
  }
  value.to_int()
}

///|
fn Cursor::count(
  self : Cursor,
  maximum : Int32,
  resource : String,
) -> Int32 raise ArchiveError {
  bounded(self.number(), maximum, resource)
}

///|
fn Cursor::bits(self : Cursor, count : Int32) -> Array[Bool] raise ArchiveError {
  let result : Array[Bool] = []
  let mut mask = 0
  let mut byte = 0
  for _ in 0..<count {
    if mask == 0 {
      byte = self.byte()
      mask = 0x80
    }
    result.push((byte & mask) != 0)
    mask = mask >> 1
  }
  result
}

///|
fn Cursor::defined(
  self : Cursor,
  count : Int32,
) -> Array[Bool] raise ArchiveError {
  match self.byte() {
    0 => self.bits(count)
    1 => Array::make(count, true)
    _ => raise Invalid(offset=self.pos - 1, reason="invalid all-defined flag")
  }
}

///|
fn Cursor::crcs(
  self : Cursor,
  count : Int32,
) -> Array[UInt32?] raise ArchiveError {
  let defined = self.defined(count)
  let result : Array[UInt32?] = []
  for present in defined {
    result.push(if present { Some(self.u32()) } else { None })
  }
  result
}

///|
fn crc32(data : BytesView) -> UInt32 {
  let mut crc = 0xffffffffU
  for byte in data {
    crc = crc ^ byte.to_uint()
    for _ in 0..<8 {
      crc = (crc >> 1) ^ (if (crc & 1U) != 0U { 0xedb88320U } else { 0U })
    }
  }
  crc ^ 0xffffffffU
}

///|
fn check_crc(
  data : BytesView,
  expected : UInt32?,
  scope : String,
) -> Unit raise ArchiveError {
  if expected is Some(value) && crc32(data) != value {
    raise Checksum(scope~)
  }
}
