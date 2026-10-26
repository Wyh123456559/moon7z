///|
/// Read an unencrypted single-volume 7z archive. Archive properties are retained
/// as opaque bytes; unsupported file/coder semantics are refused explicitly.
/// Input bytes are immutable and remain owned by the archive.
pub fn Archive::open(
  bytes : Bytes,
  limits~ : Limits = Limits::new(),
) -> Archive raise ArchiveError {
  for
    value in [
      limits.input_bytes,
      limits.header_bytes,
      limits.output_bytes,
      limits.dictionary_bytes,
      limits.entries,
      limits.working_bytes,
      limits.coders,
    ] {
    guard value >= 0 && value <= 0x3fffffff else {
      raise Invalid(
        offset=0,
        reason="limits must be between zero and 1073741823",
      )
    }
  }
  ignore(bounded(bytes.length().to_uint64(), limits.input_bytes, "input bytes"))
  let input = bytes
  let start = Cursor::new(input)
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
  check_crc(input[12:32], Some(start_crc), "start header")
  let offset = bounded(next_offset, input.length() - 32, "next header offset") +
    32
  let size = bounded(next_size, limits.header_bytes, "next header bytes")
  guard size <= input.length() - offset && offset + size == input.length() else {
    raise Invalid(offset~, reason="next header range or trailing archive data")
  }
  check_crc(input[offset:offset + size], Some(next_crc), "next header")
  if size == 0 {
    guard offset == 32 else {
      raise Invalid(offset=32, reason="empty archive contains unclaimed data")
    }
    return {
      input,
      limits,
      streams: {
        pack_offset: 0,
        pack_sizes: [],
        pack_crcs: [],
        blocks: [],
        layouts: [],
      },
      inventory: [],
      archive_properties: [],
    }
  }
  let mut header = Cursor::new(input[offset:offset + size].to_owned())
  let mut data_boundary = offset
  let mut id = header.byte()
  if id == 23 {
    let streams = read_streams(header, limits, limits.header_bytes)
    header.end()
    validate_pack_ranges(streams, offset)
    data_boundary = 32 + streams.pack_offset
    guard streams.blocks.length() == 1 && streams.blocks[0].pieces.length() == 1 else {
      raise Unsupported(feature="encoded header with multiple streams")
    }
    let decoded = decode_streams(input, streams, limits)
    let (_, crc) = streams.blocks[0].pieces[0]
    check_crc(decoded[0], crc, "encoded header substream")
    header = Cursor::new(decoded[0])
    id = header.byte()
  }
  guard id == 1 else {
    raise Invalid(
      offset=header.pos - 1,
      reason="expected decoded Header property",
    )
  }
  let mut streams : Streams = {
    layouts: [],
    pack_offset: 0,
    pack_sizes: [],
    pack_crcs: [],
    blocks: [],
  }
  id = header.byte()
  let archive_properties = if id == 2 {
    let properties = read_archive_properties(header, limits)
    id = header.byte()
    properties
  } else {
    []
  }
  if id == 4 {
    streams = read_streams(header, limits, limits.output_bytes)
    validate_pack_ranges(streams, data_boundary)
    id = header.byte()
  }
  let inventory = if id == 5 {
    let entries = read_files(header, streams, limits)
    id = header.byte()
    entries
  } else {
    []
  }
  guard id == 0 else {
    raise Unsupported(feature="archive header property \{id}")
  }
  header.end()
  let mut packed_end = 32 + streams.pack_offset
  for length in streams.pack_sizes {
    packed_end += length
  }
  guard streams.pack_offset == 0 && packed_end == data_boundary else {
    raise Unsupported(
      feature="unclaimed bytes or gaps before packed data/header",
    )
  }
  guard !inventory.is_empty() || streams.blocks.is_empty() else {
    raise Invalid(
      offset=header.pos,
      reason="archive data has no file inventory",
    )
  }
  { input, limits, streams, inventory, archive_properties, }
}

///|
fn validate_pack_ranges(
  streams : Streams,
  header_offset : Int32,
) -> Unit raise ArchiveError {
  let mut offset = 32 + streams.pack_offset
  for size in streams.pack_sizes {
    guard offset <= header_offset && size <= header_offset - offset else {
      raise Invalid(offset~, reason="packed data overlaps next header")
    }
    offset += size
  }
}

///|
/// Verify every packed stream, folder and available member CRC. This checks
/// accidental corruption, not authenticity or a cryptographic signature.
/// Requiring member CRCs refuses the first file without one before decoding;
/// this includes empty files, excludes directories and does not accept only a
/// shared folder/pack CRC as a substitute. The default behavior is unchanged.
/// Folders are decoded and checked one at a time; member contents are checked
/// through views rather than accumulated into owned Member byte copies.
pub fn Archive::verify(
  self : Archive,
  require_member_crcs~ : Bool = false,
) -> Verification raise ArchiveError {
  if require_member_crcs {
    for entry in self.inventory {
      if entry.kind == File && entry.crc32 is None {
        raise MissingChecksum(id=entry.id, name=entry.name)
      }
    }
  }
  let mut files = 0
  let mut bytes = 0
  let mut checked = 0
  let entries : Array[Array[Entry]] = Array::makei(
    self.streams.blocks.length(),
    _ => [],
  )
  for entry in self.inventory {
    if entry.block is Some(block) {
      entries[block].push(entry)
    }
    if entry.kind == File {
      files += 1
      bytes += entry.size
      if entry.crc32 is Some(_) {
        checked += 1
      }
    }
  }
  let mut start = 32 + self.streams.pack_offset
  for id in 0..<self.streams.blocks.length() {
    verify_folder(self, id, start, entries[id])
    start += packed_folder_bytes(self.streams, id)
  }
  {
    files,
    bytes,
    blocks: self.streams.blocks.length(),
    member_crcs_checked: checked,
    members_without_crc: files - checked,
  }
}

///|
/// The decoded buffer is local to this call; it is neither cached nor returned.
fn verify_folder(
  archive : Archive,
  id : Int32,
  start : Int32,
  entries : ArrayView[Entry],
) -> Unit raise ArchiveError {
  let data = decode_packed_stream(
    archive.input,
    archive.streams,
    id,
    start,
    archive.limits,
  )
  let mut offset = 0
  for entry in entries {
    check_crc(
      data[offset:offset + entry.size],
      entry.crc32,
      "member " + entry.name,
    )
    offset += entry.size
  }
}

///|
/// Return every member in archive order after verifying all available CRCs.
/// Names and metadata remain unchanged; this API never writes filesystem paths.
pub fn Archive::extract_all(self : Archive) -> Array[Member] raise ArchiveError {
  let blocks = decode_streams(self.input, self.streams, self.limits)
  let offsets = Array::make(blocks.length(), 0)
  let members : Array[Member] = []
  for entry in self.inventory {
    let bytes = if entry.block is Some(block) {
      let start = offsets[block]
      let output = blocks[block][start:start + entry.size].to_owned()
      offsets[block] += entry.size
      check_crc(output, entry.crc32, "member " + entry.name)
      output
    } else {
      b""
    }
    members.push({ entry, bytes, })
  }
  members
}
