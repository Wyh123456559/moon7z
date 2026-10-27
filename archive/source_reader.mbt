///|
/// Asynchronous selective reader with one checked folder cache. Source lifetime
/// belongs to the caller. Failed loads clear the cache and may be retried.
/// Use one reader serially; independent readers can own separate caches.
pub struct SourceReader {
  priv archive : SourceArchive
  priv starts : Array[UInt64]
  priv member_starts : Array[Int32]
  priv cache_bytes : Int32
  priv mut cached : (Int32, Bytes)?
  priv mut attempts : Int32
  priv mut hits : Int32
}

///|
pub fn SourceArchive::reader(
  self : SourceArchive,
  cache_bytes~ : Int32 = 32 * 1024 * 1024,
) -> SourceReader raise ArchiveError {
  guard cache_bytes >= 0 && cache_bytes <= 0x3fffffff else {
    raise Invalid(
      offset=0,
      reason="cache budget must be between zero and 1073741823",
    )
  }
  let offsets = Array::make(self.streams.blocks.length(), 0)
  let members : Array[Int32] = []
  for entry in self.inventory {
    if entry.block is Some(id) {
      members.push(offsets[id])
      offsets[id] += entry.size
    } else {
      members.push(0)
    }
  }
  {
    archive: self,
    starts: source_pack_starts(self.streams),
    member_starts: members,
    cache_bytes,
    cached: None,
    attempts: 0,
    hits: 0,
  }
}

///|
pub fn SourceReader::clear_cache(self : SourceReader) -> Unit {
  self.cached = None
}

///|
pub fn SourceReader::stats(self : SourceReader) -> ReaderStats {
  {
    decode_attempts: self.attempts,
    cache_hits: self.hits,
    cached_bytes: match self.cached {
      Some((_, data)) => data.length()
      None => 0
    },
  }
}

///|
async fn SourceReader::load(self : SourceReader, id : Int32) -> Bytes {
  if self.cached is Some((cached_id, data)) && cached_id == id {
    self.hits += 1
    return data
  }
  self.cached = None
  self.attempts += 1
  let archive = self.archive
  let bytes = source_folder(
    archive.source,
    archive.streams,
    id,
    self.starts[id],
    archive.limits,
    archive.crypto,
  )
  if bytes.length() <= self.cache_bytes {
    self.cached = Some((id, bytes))
  }
  bytes
}

///|
fn SourceReader::entry(
  self : SourceReader,
  id : Int32,
) -> Entry raise ArchiveError {
  guard id >= 0 && id < self.archive.inventory.length() else {
    raise NoSuchEntry(id~)
  }
  self.archive.inventory[id]
}

///|
/// Check every available CRC in the member's whole solid folder before returning
/// an owned member copy. Unselected folders remain unread and unverified.
pub async fn SourceReader::read(self : SourceReader, id : Int32) -> Member {
  let entry = self.entry(id)
  let bytes = if entry.block is Some(block) {
    let data = self.load(block)
    let start = self.member_starts[id]
    data[start:start + entry.size].to_owned()
  } else {
    b""
  }
  { entry, bytes, }
}

///|
pub async fn SourceReader::read_range(
  self : SourceReader,
  id : Int32,
  offset~ : Int32,
  length~ : Int32,
) -> Bytes {
  let entry = self.entry(id)
  guard entry.kind == File else {
    raise Unsupported(
      feature="byte range on directory entry \{id}; select a file ID",
    )
  }
  guard offset >= 0 &&
    length >= 0 &&
    offset <= entry.size &&
    length <= entry.size - offset else {
    raise InvalidRange(id~, offset~, length~, size=entry.size)
  }
  if entry.block is Some(block) {
    let data = self.load(block)
    let start = self.member_starts[id] + offset
    data[start:start + length].to_owned()
  } else {
    b""
  }
}

///|
/// A UInt64 total avoids truncating verification counts for large collections.
pub struct SourceVerification {
  files : Int32
  bytes : UInt64
  blocks : Int32
  member_crcs_checked : Int32
  members_without_crc : Int32
}

///|
pub impl ToJson for SourceVerification with fn to_json(self) {
  {
    "schema": "moon7z.source_verification.v1",
    "contents_verified": true,
    "files": Json(self.files),
    "bytes": Json(self.bytes.to_string()),
    "blocks": Json(self.blocks),
    "member_crcs_checked": Json(self.member_crcs_checked),
    "members_without_crc": Json(self.members_without_crc),
  }
}

///|
pub extend SourceVerification with ToJson::{to_json}

///|
/// Check all folders one at a time without accumulating member output copies.
/// A strict member-CRC policy is checked before any main payload read.
pub async fn SourceArchive::verify(
  self : SourceArchive,
  require_member_crcs~ : Bool = false,
) -> SourceVerification {
  let mut files = 0
  let mut bytes = 0UL
  let mut checked = 0
  for entry in self.inventory {
    if entry.kind == File {
      files += 1
      bytes += entry.size.to_uint64()
      if entry.crc32 is Some(_) {
        checked += 1
      } else if require_member_crcs {
        raise MissingChecksum(id=entry.id, name=entry.name)
      }
    }
  }
  let starts = source_pack_starts(self.streams)
  for i in 0..<starts.length() {
    ignore(
      source_folder(
        self.source,
        self.streams,
        i,
        starts[i],
        self.limits,
        self.crypto,
      ),
    )
  }
  {
    files,
    bytes,
    blocks: self.streams.blocks.length(),
    member_crcs_checked: checked,
    members_without_crc: files - checked,
  }
}
