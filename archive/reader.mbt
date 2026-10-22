///|
/// A reusable selective reader with a single most-recent-folder cache.
/// All available CRCs in a selected folder are checked before it is cached.
/// Unselected folders are not decoded or verified.
pub struct Reader {
  priv archive : Archive
  priv cache_limit : Int32
  priv pack_starts : Array[Int32]
  priv member_starts : Array[Int32]
  priv mut cached : (Int32, Bytes)?
  priv mut attempts : Int32
  priv mut hits : Int32
}

///|
/// Counters are cumulative across `clear_cache`; resident bytes exclude input
/// and returned member copies. They are not a peak-memory measurement.
pub struct ReaderStats {
  decode_attempts : Int32
  cache_hits : Int32
  cached_bytes : Int32
} derive(Eq, Debug)

///|
#deprecated
pub extend ReaderStats with Eq::{equal, not_equal}

///|
#deprecated
pub extend ReaderStats with @debug.Debug::{to_repr}

///|
/// A zero cache budget disables caching. Oversized folders are still checked
/// and read within archive limits, but are not retained after the call.
pub fn Archive::reader(
  self : Archive,
  cache_bytes~ : Int32 = 32 * 1024 * 1024,
) -> Reader raise ArchiveError {
  guard cache_bytes >= 0 && cache_bytes <= 0x3fffffff else {
    raise Invalid(
      offset=0,
      reason="cache budget must be between zero and 1073741823",
    )
  }
  let pack_starts : Array[Int32] = []
  let mut next = 32 + self.streams.pack_offset
  for size in self.streams.pack_sizes {
    pack_starts.push(next)
    next += size
  }
  let member_starts : Array[Int32] = []
  let offsets = Array::make(self.streams.blocks.length(), 0)
  for entry in self.inventory {
    if entry.block is Some(block) {
      member_starts.push(offsets[block])
      offsets[block] += entry.size
    } else {
      member_starts.push(0)
    }
  }
  {
    archive: self,
    cache_limit: cache_bytes,
    pack_starts,
    member_starts,
    cached: None,
    attempts: 0,
    hits: 0,
  }
}

///|
/// Release the resident folder without resetting cumulative counters.
pub fn Reader::clear_cache(self : Reader) -> Unit {
  self.cached = None
}

///|
/// Report decode attempts, cache hits and current resident folder bytes.
pub fn Reader::stats(self : Reader) -> ReaderStats {
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
fn Reader::load(self : Reader, id : Int32) -> Bytes raise ArchiveError {
  if self.cached is Some((cached_id, data)) && cached_id == id {
    self.hits += 1
    return data
  }
  self.cached = None
  self.attempts += 1
  let archive = self.archive
  let block = archive.streams.blocks[id]
  let start = self.pack_starts[id]
  let data = decode_packed_stream(
    archive.input,
    archive.streams,
    id,
    start,
    archive.limits,
  )
  let mut offset = 0
  for (size, crc) in block.pieces {
    check_crc(
      data[offset:offset + size],
      crc,
      "folder \{id} substream at \{offset}",
    )
    offset += size
  }
  if data.length() <= self.cache_limit {
    self.cached = Some((id, data))
  }
  data
}

///|
/// Read a member by stable ID. It may decode its whole solid folder, including
/// CRC checks for siblings. Use Archive::verify for whole-archive verification.
pub fn Reader::read(self : Reader, id : Int32) -> Member raise ArchiveError {
  self.read_many([id])[0]
}

///|
/// Copy just a file range after verifying its entire folder, including siblings.
/// This saves returned-copy space, not solid decoding work. Empty ranges in a
/// data folder still perform integrity checks; directories are not byte files.
/// Invalid requests do not change cache state. Offset at EOF requires length 0.
pub fn Reader::read_range(
  self : Reader,
  id : Int32,
  offset~ : Int32,
  length~ : Int32,
) -> Bytes raise ArchiveError {
  guard id >= 0 && id < self.archive.inventory.length() else {
    raise NoSuchEntry(id~)
  }
  let entry = self.archive.inventory[id]
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
  match entry.block {
    None => b""
    Some(block) => {
      let data = self.load(block)
      let start = self.member_starts[id] + offset
      data[start:start + length].to_owned()
    }
  }
}

///|
/// Group requests by folder, decode each selected folder at most once per call
/// and return members in request order, including duplicate IDs. All IDs and
/// total requested bytes are checked before any decode. No partial result is
/// returned on error; successfully checked cache state may survive a later error.
pub fn Reader::read_many(
  self : Reader,
  ids : ArrayView[Int32],
) -> Array[Member] raise ArchiveError {
  let archive = self.archive
  ignore(
    bounded(
      ids.length().to_uint64(),
      archive.limits.entries,
      "selected entries",
    ),
  )
  let mut remaining = archive.limits.output_bytes
  for id in ids {
    guard id >= 0 && id < archive.inventory.length() else {
      raise NoSuchEntry(id~)
    }
    let size = archive.inventory[id].size
    guard size <= remaining else {
      raise Limit(
        resource="selected output bytes",
        maximum=archive.limits.output_bytes,
      )
    }
    remaining -= size
  }
  let groups : Map[Int32, Array[(Int32, Int32)]] = Map([])
  let output : Array[Member?] = Array::make(ids.length(), None)
  for index, id in ids {
    let entry = archive.inventory[id]
    if entry.block is Some(block) {
      match groups.get(block) {
        Some(requests) => requests.push((index, id))
        None => groups[block] = [(index, id)]
      }
    } else {
      output[index] = Some({ entry, bytes: b"", })
    }
  }
  for block, requests in groups {
    let data = self.load(block)
    for (index, id) in requests {
      let entry = archive.inventory[id]
      let start = self.member_starts[id]
      output[index] = Some({
        entry,
        bytes: data[start:start + entry.size].to_owned(),
      })
    }
  }
  output.map(item => item.unwrap())
}
