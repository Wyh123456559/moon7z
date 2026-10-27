///|
/// Read a single-volume 7z archive, optionally with a UTF-16 encoded password.
/// A plain-header encrypted archive can be listed without a password; encrypted
/// headers require it at opening. Archive properties are retained
/// as opaque bytes; unsupported file/coder semantics are refused explicitly.
/// Input bytes are immutable and remain owned by the archive.
pub fn Archive::open(
  bytes : Bytes,
  limits~ : Limits = Limits::new(),
  password? : String,
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
      limits.kdf_rounds,
      limits.kdf_bytes,
      limits.password_bytes,
      limits.file_property_records,
    ] {
    guard value >= 0 && value <= 0x3fffffff else {
      raise Invalid(
        offset=0,
        reason="limits must be between zero and 1073741823",
      )
    }
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
      auxiliary: [],
      file_extensions: [],
      crypto,
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
  let regions : Array[(Int32, Int32)] = []
  let mut id = header.byte()
  if id == 23 {
    let streams = read_streams(header, limits, limits.header_bytes)
    header.end()
    validate_pack_ranges(streams, offset)
    regions.push(packed_region(streams))
    let decoded = decode_metadata_streams(input, streams, limits, crypto)
    guard decoded.length() <= 1 else {
      raise Invalid(
        offset=header.pos,
        reason="encoded header must have at most one folder output",
      )
    }
    if decoded.is_empty() {
      check_regions(regions, offset)
      return {
        auxiliary: [],
        file_extensions: [],
        crypto,
        input,
        limits,
        streams,
        inventory: [],
        archive_properties: [],
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
  let auxiliary = if id == 3 {
    let additional = read_streams(
      header,
      limits,
      limits.header_bytes - header.data.length(),
    )
    validate_pack_ranges(additional, offset)
    regions.push(packed_region(additional))
    let buffers = decode_metadata_streams(input, additional, limits, crypto)
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
    file_extensions,
    auxiliary,
    crypto,
    input,
    limits,
    streams,
    inventory,
    archive_properties,
  }
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
    crypto=Some(archive.crypto),
  )
  let mut offset = 0
  for entry in entries {
    check_crc(
      data[offset:offset + entry.size],
      entry.crc32,
      "member " + entry.name,
    ) catch {
      error => raise encrypted_error(archive.streams.blocks[id], error)
    }
    offset += entry.size
  }
}

///|
/// Return every member in archive order after verifying all available CRCs.
/// Names and metadata remain unchanged; this API never writes filesystem paths.
pub fn Archive::extract_all(self : Archive) -> Array[Member] raise ArchiveError {
  let blocks = decode_streams(
    self.input,
    self.streams,
    self.limits,
    crypto=Some(self.crypto),
  )
  let offsets = Array::make(blocks.length(), 0)
  let members : Array[Member] = []
  for entry in self.inventory {
    let bytes = if entry.block is Some(block) {
      let start = offsets[block]
      let output = blocks[block][start:start + entry.size].to_owned()
      offsets[block] += entry.size
      check_crc(output, entry.crc32, "member " + entry.name) catch {
        error => raise encrypted_error(self.streams.blocks[block], error)
      }
      output
    } else {
      b""
    }
    members.push({ entry, bytes, })
  }
  members
}
