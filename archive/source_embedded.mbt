///|
/// An embedded archive with live, exact envelope views. No executable is run.
/// The original source is reconstructible as concat([prefix, payload, suffix]);
/// views and readers require the original source to stay open and stable.
pub struct SourceEmbeddedArchive {
  offset : UInt64
  prefix : SeekableInput
  payload : SeekableInput
  suffix : SeekableInput
  archive : SourceArchive
}

///|
fn check_embedded_source_policy(
  source : SeekableInput,
  limits : Limits,
  maximum : UInt64,
) -> Unit raise ArchiveError {
  limits.validate()
  guard source.size <= maximum else {
    raise SourceLimit(resource="embedded source bytes", maximum~)
  }
  guard limits.input_bytes >= 32 else {
    raise Limit(
      resource="embedded source read bytes",
      maximum=limits.input_bytes,
    )
  }
  guard source.size >= 32UL else {
    raise SourceRead(
      offset=0UL,
      reason="embedded source is shorter than a 32-byte start header",
    )
  }
}

///|
/// Scan bounded windows for the first complete start header with a valid CRC.
/// Candidate starts are in 0..<search_bytes; its header may cross that boundary.
/// Read failures propagate. A credible candidate's failure is never skipped.
pub async fn SourceEmbeddedArchive::open(
  source : SeekableInput,
  limits~ : Limits = Limits::new(),
  max_source_bytes~ : UInt64 = 1099511627776UL,
  max_output_bytes~ : UInt64 = 17179869184UL,
  search_bytes~ : UInt64 = 1048576UL,
  password? : String,
) -> SourceEmbeddedArchive {
  check_embedded_source_policy(source, limits, max_source_bytes)
  let eligible = source.size - 31UL
  let stop = if search_bytes < eligible { search_bytes } else { eligible }
  let span = limits.input_bytes.min(65536) - 31
  let mut base = 0UL
  // Invariant: [0, base) has no CRC-valid complete start header. Each window
  // checks at least one new start and its 31 lookahead bytes fit in the source.
  while base < stop {
    let count = if stop - base < span.to_uint64() {
      (stop - base).to_int()
    } else {
      span
    }
    let window = source.read_at(base, count + 31)
    if find_source_signature(window, count) is Some(found) {
      return SourceEmbeddedArchive::open_at(
        source,
        base + found.to_uint64(),
        limits~,
        max_source_bytes~,
        max_output_bytes~,
        password?,
      )
    }
    base += count.to_uint64()
  }
  raise SourceSignatureNotFound(searched_bytes=stop)
}

///|
fn find_source_signature(window : Bytes, candidates : Int32) -> Int32? {
  for offset in 0..<candidates {
    if window[offset] != b'7' ||
      window[offset + 1] != b'z' ||
      window[offset + 2] != b'\xbc' ||
      window[offset + 3] != b'\xaf' ||
      window[offset + 4] != b'\x27' ||
      window[offset + 5] != b'\x1c' {
      continue
    }
    let stored = window[offset + 8].to_uint() |
      (window[offset + 9].to_uint() << 8) |
      (window[offset + 10].to_uint() << 16) |
      (window[offset + 11].to_uint() << 24)
    if crc32(window[offset + 12:offset + 32]) == stored {
      return Some(offset)
    }
  }
  None
}

///|
fn source_embedded_extent(
  header : Bytes,
  offset : UInt64,
  available : UInt64,
  limits : Limits,
) -> UInt64 raise ArchiveError {
  let r = Cursor::new(header)
  guard r.take(6) == b"7z\xbc\xaf\x27\x1c" else {
    raise position_error(
      offset, "expected 7z signature at the supplied source offset",
    )
  }
  let major = r.byte()
  let minor = r.byte()
  guard major == 0 && minor <= 4 else {
    raise Unsupported(feature="7z version \{major}.\{minor}")
  }
  let stored = r.u32()
  let next_offset = r.u64()
  let next_size = r.u64()
  ignore(r.u32())
  check_crc(header[12:32], Some(stored), "embedded source start header")
  guard next_offset <= 0xffffffffffffffdfUL &&
    next_size <= 0xffffffffffffffdfUL - next_offset else {
    raise SourceRead(offset~, reason="embedded archive extent overflows UInt64")
  }
  ignore(
    bounded(
      next_size,
      limits.header_bytes.min(limits.input_bytes),
      "embedded source next header bytes",
    ),
  )
  let extent = 32UL + next_offset + next_size
  guard extent <= available else {
    raise SourceRead(
      offset~,
      reason="embedded archive extends beyond input; the input or last volume may be truncated",
    )
  }
  extent
}

///|
/// Open a supplied UInt64 offset without scanning the prefix. The exact archive
/// extent is validated before opening a bounded view through SourceArchive.
pub async fn SourceEmbeddedArchive::open_at(
  source : SeekableInput,
  offset : UInt64,
  limits~ : Limits = Limits::new(),
  max_source_bytes~ : UInt64 = 1099511627776UL,
  max_output_bytes~ : UInt64 = 17179869184UL,
  password? : String,
) -> SourceEmbeddedArchive {
  check_embedded_source_policy(source, limits, max_source_bytes)
  let header = source.read_at(offset, 32)
  let extent = source_embedded_extent(
    header,
    offset,
    source.size - offset,
    limits,
  )
  let payload = source.slice(offset, extent)
  let archive = SourceArchive::open(
    payload,
    limits~,
    max_source_bytes~,
    max_output_bytes~,
    password?,
  )
  let end = offset + extent // extent validation proves this cannot overflow.
  {
    offset,
    prefix: source.slice(0UL, offset),
    payload,
    suffix: source.slice(end, source.size - end),
    archive,
  }
}

///|
/// Layout and decoded inventory only. Envelope bytes remain in the live views,
/// are not embedded into JSON, and are neither executed nor authenticated.
pub fn SourceEmbeddedArchive::inventory_json(
  self : SourceEmbeddedArchive,
) -> Json {
  {
    "schema": "moon7z.source_embedded_inventory.v1",
    "contents_verified": false,
    "envelope_verified": false,
    "envelope_bytes_included": false,
    "offset": Json(self.offset.to_string()),
    "source_bytes": Json(
      (self.prefix.size + self.payload.size + self.suffix.size).to_string(),
    ),
    "prefix_bytes": Json(self.prefix.size.to_string()),
    "archive_bytes": Json(self.payload.size.to_string()),
    "suffix_bytes": Json(self.suffix.size.to_string()),
    "archive": self.archive.inventory_json(),
  }
}
