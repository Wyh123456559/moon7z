///|
/// Exact asynchronous random access. The callback must return exactly the
/// requested bytes from a stable source; I/O errors propagate to the caller.
/// No source bytes are read by construction. Caller owns the source lifetime.
///
/// ```mbt check
/// test {
///   let source = @archive.SeekableInput::new(0UL, (_, _) => b"")
///   assert_eq(source.size, 0UL)
/// }
/// ```
pub struct SeekableInput {
  size : UInt64
  priv fetch : async (UInt64, Int32) -> Bytes
}

///|
pub fn SeekableInput::new(
  size : UInt64,
  read_at : async (UInt64, Int32) -> Bytes,
) -> SeekableInput {
  { size, fetch: read_at, }
}

///|
/// Retain an exact UInt64 subrange without reading or allocating its bytes.
/// Offsets passed to the resulting input are relative to this view.
pub fn SeekableInput::slice(
  self : SeekableInput,
  offset : UInt64,
  size : UInt64,
) -> SeekableInput raise ArchiveError {
  guard offset <= self.size && size <= self.size - offset else {
    raise SourceRead(
      offset~,
      reason="source view is outside the declared input",
    )
  }
  SeekableInput::new(size, async fn(relative, length) {
    // The view and exact-read guards prove offset + relative <= self.size.
    self.read_at(offset + relative, length)
  })
}

///|
fn validate_source_range(
  size : UInt64,
  offset : UInt64,
  length : Int32,
) -> Unit raise ArchiveError {
  guard length >= 0 &&
    length <= 0x3fffffff &&
    offset <= size &&
    length.to_uint64() <= size - offset else {
    raise SourceRead(
      offset~,
      reason="requested range is outside the declared source",
    )
  }
}

///|
pub async fn SeekableInput::read_at(
  self : SeekableInput,
  offset : UInt64,
  length : Int32,
) -> Bytes {
  validate_source_range(self.size, offset, length)
  if length == 0 {
    return b""
  }
  let bytes = (self.fetch)(offset, length)
  guard bytes.length() == length else {
    raise SourceRead(
      offset~,
      reason="read callback returned \{bytes.length()} bytes, expected exactly \{length}; the source may be truncated or changed",
    )
  }
  bytes
}

///|
fn position_error(offset : UInt64, reason : String) -> ArchiveError {
  if offset <= 0x3fffffffUL {
    Invalid(offset=offset.to_int(), reason~)
  } else {
    SourceRead(offset~, reason~)
  }
}

///|
/// Compose exact sources without assembling their contents. An individual read
/// may cross any number of parts. Empty sources retain their zero-byte place;
/// cumulative UInt64 overflow is refused before invoking any callback.
pub fn SeekableInput::concat(
  parts : ArrayView[SeekableInput],
  max_parts~ : Int32 = 1024,
) -> SeekableInput raise ArchiveError {
  guard max_parts >= 1 && max_parts <= 0x3fffffff else {
    raise Invalid(
      offset=0,
      reason="source part limit must be between 1 and 1073741823",
    )
  }
  guard parts.length() > 0 else {
    raise SourceRead(offset=0UL, reason="source part list is empty")
  }
  guard parts.length() <= max_parts else {
    raise Limit(resource="source part count", maximum=max_parts)
  }
  let owned = parts.to_owned()
  if owned.length() == 1 {
    return owned[0]
  }
  let starts : Array[UInt64] = []
  let ends : Array[UInt64] = []
  let mut total = 0UL
  for part in owned {
    guard part.size <= 0xffffffffffffffffUL - total else {
      raise SourceRead(
        offset=total,
        reason="combined source length overflows UInt64",
      )
    }
    starts.push(total)
    total += part.size
    ends.push(total)
  }
  SeekableInput::new(total, async fn(offset, length) {
    let mut low = 0
    let mut high = ends.length()
    // Invariant: ends before low are <= offset; ends from high are > offset.
    // Each iteration shortens [low, high); the exact-read guard ensures a hit.
    while low < high {
      let mid = low + (high - low) / 2
      if ends[mid] <= offset {
        low = mid + 1
      } else {
        high = mid
      }
    }
    let result = @buffer.Buffer(size_hint=length)
    let mut cursor = offset
    let mut remaining = length
    // Invariant: cursor = offset + (length - remaining), result holds that
    // exact prefix, and i identifies the next part. Empty parts advance i;
    // positive parts decrease remaining. A validated range fits the suffix.
    for i = low; remaining > 0; i = i + 1 {
      let relative = cursor - starts[i]
      let available = owned[i].size - relative
      let take = if available < remaining.to_uint64() {
        available.to_int()
      } else {
        remaining
      }
      if take > 0 {
        result.write_bytes(owned[i].read_at(relative, take))
      }
      cursor += take.to_uint64()
      remaining -= take
    }
    result.to_bytes()
  })
}
