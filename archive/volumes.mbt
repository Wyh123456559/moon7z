///|
/// Explicit ordered volume names; construction validates numbering before I/O.
/// Numeric suffixes have at least two digits and begin at zero or one.
pub struct VolumeSequence {
  priv ordered_names : Array[String]
}

///|
/// Each physical part's location in the logical archive. Offsets are decimal
/// strings in JSON; current reading remains bounded by Limits.input_bytes.
pub struct VolumeInfo {
  name : String
  offset : UInt64
  bytes : Int32
} derive(Debug, Eq)

///|
pub extend VolumeInfo with @debug.Debug::{to_repr}

///|
pub extend VolumeInfo with Eq::{equal, not_equal}

///|
pub struct SplitArchive {
  archive : Archive
  priv physical_parts : Array[VolumeInfo]
}

///|
/// Preserve caller order, refusing gaps, duplicates, mixed prefixes/padding or
/// reordered names. No sorting or filesystem guessing takes place.
///
/// ```mbt check
/// test {
///   let sequence = @archive.VolumeSequence::new(["assets.7z.001", "assets.7z.002"])
///   assert_eq(sequence.names(), ["assets.7z.001", "assets.7z.002"])
/// }
/// ```
pub fn VolumeSequence::new(
  names : ArrayView[String],
  max_volumes~ : Int32 = 1024,
) -> VolumeSequence raise ArchiveError {
  guard max_volumes >= 1 && max_volumes <= 0x3fffffff else {
    raise VolumeError(
      index=0,
      reason="max_volumes must be between 1 and 1073741823",
    )
  }
  guard names.length() > 0 else {
    raise VolumeError(index=0, reason="the volume list is empty")
  }
  guard names.length() <= max_volumes else {
    raise Limit(resource="volume count", maximum=max_volumes)
  }
  let first = names[0]
  guard !first.contains("\u0000") &&
    !first.contains("/") &&
    !first.contains("\\") else {
    raise VolumeError(
      index=0,
      reason="volume labels must be single filenames without NUL",
    )
  }
  let pieces = first.split(".").to_array()
  guard pieces.length() >= 2 else {
    raise VolumeError(
      index=0,
      reason="expected a numeric volume suffix such as .001",
    )
  }
  let digits = pieces[pieces.length() - 1].to_owned()
  let prefix = pieces[:pieces.length() - 1].join(".") + "."
  guard prefix.length() > 1 && digits.length() >= 2 && digits.length() <= 10 else {
    raise VolumeError(
      index=0,
      reason="expected a nonempty basename and a 2–10 digit volume suffix",
    )
  }
  let mut initial = 0
  for ch in digits {
    guard ch >= '0' && ch <= '9' && initial <= 100000000 else {
      raise VolumeError(
        index=0,
        reason="expected numeric volume numbering starting at zero or one",
      )
    }
    initial = initial * 10 + ch.to_int() - '0'.to_int()
  }
  guard initial == 0 || initial == 1 else {
    raise VolumeError(
      index=0,
      reason="the first supplied volume must be numbered zero or one; earlier volumes are missing",
    )
  }
  for i, name in names {
    let value = (initial + i).to_string()
    let suffix = "0".repeat((digits.length() - value.length()).max(0)) + value
    let expected = prefix + suffix
    guard name == expected else {
      raise VolumeError(
        index=i,
        reason="expected \{expected}, got \{name}; a volume is missing, duplicated, reordered or belongs to another set",
      )
    }
  }
  { ordered_names: names.to_owned(), }
}

///|
pub fn VolumeSequence::names(self : VolumeSequence) -> Array[String] {
  self.ordered_names.copy()
}

///|
/// Join every supplied part after checking count, nonempty parts and cumulative
/// input size. Variable part sizes and splits inside the 32-byte header work.
/// A short final input or extra appended bytes is refused; nothing is discarded.
pub fn VolumeSequence::open(
  self : VolumeSequence,
  parts : ArrayView[Bytes],
  limits~ : Limits = Limits::new(),
  password? : String,
) -> SplitArchive raise ArchiveError {
  limits.validate()
  guard parts.length() == self.ordered_names.length() else {
    raise VolumeError(
      index=parts.length().min(self.ordered_names.length()),
      reason="expected \{self.ordered_names.length()} parts, received \{parts.length()}",
    )
  }
  let info : Array[VolumeInfo] = []
  let mut total = 0
  for i, bytes in parts {
    guard bytes.length() > 0 else {
      raise VolumeError(
        index=i,
        reason="volume \{self.ordered_names[i]} is empty",
      )
    }
    guard bytes.length() <= limits.input_bytes - total else {
      raise Limit(
        resource="combined volume input bytes",
        maximum=limits.input_bytes,
      )
    }
    info.push({
      name: self.ordered_names[i],
      offset: total.to_uint64(),
      bytes: bytes.length(),
    })
    total += bytes.length()
  }
  let joined = @buffer.Buffer(size_hint=total)
  for part in parts {
    joined.write_bytes(part)
  }
  let bytes = joined.to_bytes()
  guard bytes.length() >= 32 else {
    raise VolumeError(
      index=parts.length() - 1,
      reason="combined input lacks a complete 7z start header; the last volume may be missing or truncated",
    )
  }
  let header = Cursor::new(bytes[12:32].to_owned())
  let next_offset = header.u64()
  let next_size = header.u64()
  // Check a credible start header before diagnosing a missing final part.
  if bytes[:6].to_owned() == b"7z\xbc\xaf\x27\x1c" &&
    bytes[6] == b'\x00' &&
    bytes[7] <= b'\x04' &&
    crc32(bytes[12:32]) == Cursor::new(bytes[8:12].to_owned()).u32() &&
    (
      next_offset > (total - 32).to_uint64() ||
      next_size > (total - 32).to_uint64() - next_offset
    ) {
    raise VolumeError(
      index=parts.length() - 1,
      reason="7z header extends beyond supplied parts; the last volume is missing or truncated",
    )
  }
  { archive: Archive::open(bytes, limits~, password?), physical_parts: info, }
}

///|
pub fn SplitArchive::volumes(self : SplitArchive) -> Array[VolumeInfo] {
  self.physical_parts.copy()
}

///|
pub fn SplitArchive::inventory_json(self : SplitArchive) -> Json {
  {
    "schema": "moon7z.split_inventory.v1",
    "contents_verified": false,
    "volumes": Json(
      self.physical_parts.map(part => {
        "name": Json(part.name),
        "offset": Json(part.offset.to_string()),
        "bytes": Json(part.bytes),
      }),
    ),
    "archive": self.archive.inventory_json(),
  }
}
