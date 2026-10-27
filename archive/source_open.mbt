///|
/// Metadata and a live seekable source. Physical positions stay UInt64 while
/// individual reads and decoded folders stay bounded. Use a reader to import
/// selected members; opening reads headers/metadata but never main payloads.
pub struct SourceArchive {
  priv source : SeekableInput
  priv limits : Limits
  priv crypto : CryptState
  priv streams : Streams
  priv inventory : Array[Entry]
  priv auxiliary : Array[Bytes]
  priv archive_properties : Array[ArchiveProperty]
  priv file_extensions : Array[FileProperty]
}

///|
/// The source-size policy is distinct from Limits.input_bytes, which bounds
/// one packed folder/read in this API. Limits.output_bytes bounds one folder,
/// rather than the sum of an archive's files. I/O errors propagate unchanged.
pub async fn SourceArchive::open(
  source : SeekableInput,
  limits~ : Limits = Limits::new(),
  max_source_bytes~ : UInt64 = 1099511627776UL,
  max_output_bytes~ : UInt64 = 17179869184UL,
  password? : String,
) -> SourceArchive {
  limits.validate()
  guard source.size <= max_source_bytes else {
    raise SourceLimit(resource="source bytes", maximum=max_source_bytes)
  }
  guard source.size >= 32UL else {
    raise SourceRead(
      offset=0UL,
      reason="source is shorter than a 32-byte 7z start header",
    )
  }
  guard limits.input_bytes >= 32 else {
    raise Limit(resource="source read bytes", maximum=limits.input_bytes)
  }
  let secret = match password {
    None => None
    Some(text) => {
      guard text.length() <= limits.password_bytes / 2 else {
        raise Limit(
          resource="UTF-16 password bytes",
          maximum=limits.password_bytes,
        )
      }
      Some(@utf16.encode(text[:], endianness=Little, bom=false))
    }
  }
  let crypto = CryptState::new(secret, limits)
  let start_bytes = source.read_at(0UL, 32)
  let start = Cursor::new(start_bytes)
  guard start.take(6) == b"7z\xbc\xaf\x27\x1c" else {
    raise Invalid(offset=0, reason="expected 7z signature at byte zero")
  }
  let major = start.byte()
  let minor = start.byte()
  guard major == 0 && minor <= 4 else {
    raise Unsupported(feature="7z version \{major}.\{minor}")
  }
  let start_crc = start.u32()
  let next_offset = start.u64()
  let next_size = start.u64()
  let next_crc = start.u32()
  check_crc(start_bytes[12:32], Some(start_crc), "start header")
  let (offset, size) = source_header_range(
    source.size,
    next_offset,
    next_size,
    limits,
  )
  let next = source.read_at(offset, size)
  check_crc(next, Some(next_crc), "next header")
  let regions : Array[(UInt64, UInt64)] = []
  let mut streams : Streams = {
    pack_offset: 0UL,
    pack_sizes: [],
    pack_crcs: [],
    blocks: [],
    layouts: [],
  }
  if size == 0 {
    guard offset == 32UL else {
      raise Unsupported(feature="unclaimed bytes before empty header")
    }
    return {
      source,
      limits,
      crypto,
      streams,
      inventory: [],
      auxiliary: [],
      archive_properties: [],
      file_extensions: [],
    }
  }
  let mut header = Cursor::new(next)
  let mut id = header.byte()
  if id == 23 {
    let encoded = read_streams(
      header,
      limits,
      limits.header_bytes,
      source_mode=true,
    )
    header.end()
    validate_pack_ranges(encoded, offset)
    regions.push(packed_region(encoded))
    let decoded = source_metadata(
      source,
      encoded,
      limits,
      crypto,
      limits.header_bytes,
    )
    guard decoded.length() <= 1 else {
      raise Invalid(
        offset=header.pos,
        reason="encoded header must have at most one folder output",
      )
    }
    if decoded.is_empty() {
      check_regions(regions, offset)
      return {
        source,
        limits,
        crypto,
        streams,
        inventory: [],
        auxiliary: [],
        archive_properties: [],
        file_extensions: [],
      }
    }
    header = Cursor::new(decoded[0])
    id = header.byte()
  }
  guard id == 1 else {
    raise Invalid(
      offset=header.pos - 1,
      reason="expected decoded Header property",
    )
  }
  id = header.byte()
  let archive_properties = if id == 2 {
    let records = read_archive_properties(header, limits)
    id = header.byte()
    records
  } else {
    []
  }
  let auxiliary = if id == 3 {
    let budget = limits.header_bytes - header.data.length()
    let additional = read_streams(header, limits, budget, source_mode=true)
    validate_pack_ranges(additional, offset)
    regions.push(packed_region(additional))
    let buffers = source_metadata(source, additional, limits, crypto, budget)
    id = header.byte()
    buffers
  } else {
    []
  }
  if id == 4 {
    streams = read_streams(
      header,
      limits,
      limits.output_bytes,
      buffers=auxiliary,
      source_mode=true,
    )
    validate_pack_ranges(streams, offset)
    regions.push(packed_region(streams))
    id = header.byte()
  }
  let file_extensions : Array[FileProperty] = []
  let inventory = if id == 5 {
    let entries = read_files(
      header,
      streams,
      limits,
      buffers=auxiliary,
      properties=file_extensions,
    )
    id = header.byte()
    entries
  } else {
    []
  }
  guard id == 0 else {
    raise Unsupported(feature="archive header property \{id}")
  }
  header.end()
  check_regions(regions, offset)
  let mut total_output = 0UL
  for entry in inventory {
    guard entry.size.to_uint64() <= max_output_bytes - total_output else {
      raise SourceLimit(
        resource="total declared output bytes",
        maximum=max_output_bytes,
      )
    }
    total_output += entry.size.to_uint64()
  }
  guard !inventory.is_empty() || streams.blocks.is_empty() else {
    raise Invalid(
      offset=header.pos,
      reason="archive data has no file inventory",
    )
  }
  crypto.encrypted = crypto.encrypted ||
    streams.blocks.any(block => {
      block.coders.any(coder => coder.codec_id == b"\x06\xf1\x07\x01")
    })
  {
    source,
    limits,
    crypto,
    streams,
    inventory,
    auxiliary,
    archive_properties,
    file_extensions,
  }
}

///|
fn source_header_range(
  total : UInt64,
  next_offset : UInt64,
  next_size : UInt64,
  limits : Limits,
) -> (UInt64, Int32) raise ArchiveError {
  guard total >= 32UL &&
    next_offset <= total - 32UL &&
    next_size == total - 32UL - next_offset else {
    raise SourceRead(
      offset=next_offset,
      reason="next-header extent exceeds input or leaves trailing bytes",
    )
  }
  let size = bounded(
    next_size,
    limits.header_bytes.min(limits.input_bytes),
    "source next header bytes",
  )
  (32UL + next_offset, size)
}

///|
fn source_pack_starts(streams : Streams) -> Array[UInt64] {
  let starts : Array[UInt64] = []
  let mut offset = 32UL + streams.pack_offset
  for id in 0..<streams.blocks.length() {
    starts.push(offset)
    let (first, count) = pack_range(streams, id)
    for index in first..<(first + count) {
      offset += streams.pack_sizes[index].to_uint64()
    }
  }
  starts
}

///|
async fn source_folder(
  source : SeekableInput,
  streams : Streams,
  id : Int32,
  start : UInt64,
  limits : Limits,
  crypto : CryptState,
) -> Bytes {
  let (first, count) = pack_range(streams, id)
  let mut total = 0
  for i in first..<(first + count) {
    guard streams.pack_sizes[i] <= limits.input_bytes - total else {
      raise Limit(
        resource="source packed folder bytes",
        maximum=limits.input_bytes,
      )
    }
    total += streams.pack_sizes[i]
  }
  let packed : Array[Bytes] = []
  let mut offset = start
  for i in first..<(first + count) {
    let size = streams.pack_sizes[i]
    let bytes = source.read_at(offset, size)
    check_crc(bytes, streams.pack_crcs[i], "packed stream \{i}")
    packed.push(bytes)
    offset += size.to_uint64()
  }
  let decoded = decode_packed_parts(
    streams,
    id,
    packed,
    limits,
    crypto=Some(crypto),
  )
  let mut piece_start = 0
  for (size, crc) in streams.blocks[id].pieces {
    check_crc(
      decoded[piece_start:piece_start + size],
      crc,
      "folder \{id} substream at \{piece_start}",
    ) catch {
      error => raise encrypted_error(streams.blocks[id], error)
    }
    piece_start += size
  }
  decoded
}

///|
async fn source_metadata(
  source : SeekableInput,
  streams : Streams,
  limits : Limits,
  crypto : CryptState,
  budget : Int32,
) -> Array[Bytes] {
  let mut remaining = budget
  for block in streams.blocks {
    guard block.size <= remaining else {
      raise Limit(resource="decoded source metadata bytes", maximum=budget)
    }
    remaining -= block.size
  }
  let starts = source_pack_starts(streams)
  let result : Array[Bytes] = []
  for i in 0..<starts.length() {
    result.push(source_folder(source, streams, i, starts[i], limits, crypto))
  }
  result
}

///|
pub fn SourceArchive::entries(self : SourceArchive) -> Array[Entry] {
  self.inventory.copy()
}

///|
pub fn SourceArchive::properties(
  self : SourceArchive,
) -> Array[ArchiveProperty] {
  self.archive_properties.copy()
}

///|
pub fn SourceArchive::metadata_streams(self : SourceArchive) -> Array[Bytes] {
  self.auxiliary.copy()
}

///|
pub fn SourceArchive::file_properties(
  self : SourceArchive,
) -> Array[FileProperty] {
  self.file_extensions.copy()
}

///|
pub fn SourceArchive::is_encrypted(self : SourceArchive) -> Bool {
  self.crypto.encrypted
}

///|
pub fn SourceArchive::source_size(self : SourceArchive) -> UInt64 {
  self.source.size
}

///|
pub fn SourceArchive::inventory_json(self : SourceArchive) -> Json {
  {
    "schema": "moon7z.source_inventory.v1",
    "contents_verified": false,
    "source_bytes": Json(self.source.size.to_string()),
    "entries": Json(self.inventory.map(entry => entry.to_json())),
    "archive_properties": Json(
      self.archive_properties.map(record => record.to_json()),
    ),
    "metadata_streams": metadata_streams_json(self.auxiliary),
    "file_properties": Json(
      self.file_extensions.map(record => record.to_json()),
    ),
  }
}

///|
pub fn SourceArchive::plan_contents(
  self : SourceArchive,
) -> ContentPlan raise ArchiveError {
  guard self.inventory.is_empty() || self.file_extensions.is_empty() else {
    raise UnsafePath(
      path="<file metadata>",
      reason="opaque file properties have unknown per-entry semantics; inspect file_properties() and use an explicit import policy",
    )
  }
  plan_entries(self.inventory)
}
