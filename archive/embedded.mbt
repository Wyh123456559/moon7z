///|
/// An embedded 7z import preserves all surrounding input as opaque bytes.
/// The prefix is not executed or interpreted as a trusted executable. The
/// parsed archive covers exactly `payload`, never the prefix or suffix.
pub struct EmbeddedArchive {
  prefix : Bytes
  payload : Bytes
  suffix : Bytes
  archive : Archive
}

///|
/// Find the first complete 7z start header whose start CRC is valid. Candidate
/// starting offsets are in `0..<search_bytes`; the 32-byte header may cross the
/// search boundary. The complete input remains subject to Limits.input_bytes.
/// A credible candidate's version, extent, metadata or password failure is
/// returned immediately, rather than falling through to a later archive.
///
/// ```mbt check
/// test {
///   let missing = try {
///     ignore(@archive.EmbeddedArchive::open(b"\x00".repeat(32)))
///     false
///   } catch {
///     @archive.SignatureNotFound(..) => true
///     _ => false
///   }
///   assert_true(missing)
/// }
/// ```
pub fn EmbeddedArchive::open(
  input : Bytes,
  limits~ : Limits = Limits::new(),
  password? : String,
  search_bytes~ : Int32 = 1024 * 1024,
) -> EmbeddedArchive raise ArchiveError {
  limits.validate()
  ignore(bounded(input.length().to_uint64(), limits.input_bytes, "input bytes"))
  guard search_bytes >= 0 && search_bytes <= 0x3fffffff else {
    raise Invalid(
      offset=0,
      reason="search_bytes must be between zero and 1073741823",
    )
  }
  guard input.length() >= 32 else {
    raise Invalid(
      offset=0,
      reason="embedded input is shorter than a 32-byte 7z start header",
    )
  }
  let eligible = input.length() - 31
  let stop = if search_bytes < eligible { search_bytes } else { eligible }
  for offset in 0..<stop {
    if input[offset] != b'7' ||
      input[offset + 1] != b'z' ||
      input[offset + 2] != b'\xbc' ||
      input[offset + 3] != b'\xaf' ||
      input[offset + 4] != b'\x27' ||
      input[offset + 5] != b'\x1c' {
      continue
    }
    let stored = Cursor::new(input[offset + 8:offset + 12].to_owned()).u32()
    if crc32(input[offset + 12:offset + 32]) != stored {
      continue
    }
    return EmbeddedArchive::open_at(input, offset, limits~, password?)
  }
  raise SignatureNotFound(searched_bytes=stop)
}

///|
/// Open a known archive offset without discovery. All header and payload checks
/// are identical to ordinary Archive::open; original envelope bytes are retained.
pub fn EmbeddedArchive::open_at(
  input : Bytes,
  offset : Int32,
  limits~ : Limits = Limits::new(),
  password? : String,
) -> EmbeddedArchive raise ArchiveError {
  limits.validate()
  ignore(bounded(input.length().to_uint64(), limits.input_bytes, "input bytes"))
  guard offset >= 0 && offset <= input.length() && input.length() - offset >= 32 else {
    raise Invalid(
      offset~,
      reason="embedded offset does not contain a complete 7z start header",
    )
  }
  let header = Cursor::new(input[offset:offset + 32].to_owned())
  guard header.take(6) == b"7z\xbc\xaf\x27\x1c" else {
    raise Invalid(
      offset~,
      reason="expected 7z signature at the supplied embedded offset",
    )
  }
  let major = header.byte()
  let minor = header.byte()
  guard major == 0 && minor <= 4 else {
    raise Unsupported(feature="7z version \{major}.\{minor}")
  }
  let start_crc = header.u32()
  let next_offset = header.u64()
  let next_size = header.u64()
  ignore(header.u32())
  check_crc(
    input[offset + 12:offset + 32],
    Some(start_crc),
    "embedded start header",
  )
  guard next_offset <= 0xffffffffffffffdfUL &&
    next_size <= 0xffffffffffffffdfUL - next_offset else {
    raise Invalid(
      offset=offset + 12,
      reason="embedded archive extent overflows UInt64",
    )
  }
  ignore(bounded(next_size, limits.header_bytes, "next header bytes"))
  let extent = 32UL + next_offset + next_size
  guard extent <= (input.length() - offset).to_uint64() else {
    raise Invalid(
      offset=offset + 12,
      reason="embedded archive extent exceeds the supplied input; the archive may be truncated",
    )
  }
  let end = offset + extent.to_int()
  let payload = input[offset:end].to_owned()
  let archive = Archive::open(payload, limits~, password?)
  {
    prefix: input[:offset].to_owned(),
    payload,
    suffix: input[end:].to_owned(),
    archive,
  }
}

///|
/// Inventory preserves original wrapper bytes as Base64. False verification
/// flags do not change if a caller previously verified the embedded archive.
/// Surrounding executable/configuration/trailer bytes are not authenticated.
pub fn EmbeddedArchive::inventory_json(self : EmbeddedArchive) -> Json {
  {
    "schema": "moon7z.embedded_inventory.v1",
    "contents_verified": false,
    "envelope_verified": false,
    "offset": Json(self.prefix.length()),
    "archive_bytes": Json(self.payload.length()),
    "prefix_base64": Json(@base64.encode(self.prefix)),
    "suffix_base64": Json(@base64.encode(self.suffix)),
    "archive": self.archive.inventory_json(),
  }
}
