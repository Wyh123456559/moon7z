///|
/// Validate the entire request before I/O/cache changes. Return owned members
/// in request order, including duplicate IDs. Limits.entries/output_bytes bound
/// request count and combined copies. Each selected folder decodes at most once
/// per call, even with caching disabled. Unselected folders remain unchecked.
pub async fn SourceReader::read_many(
  self : SourceReader,
  ids : ArrayView[Int32],
) -> Array[Member] {
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
    let entry = self.entry(id)
    guard entry.size <= remaining else {
      raise Limit(
        resource="selected output bytes",
        maximum=archive.limits.output_bytes,
      )
    }
    remaining -= entry.size
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

///|
/// Read duplicate/overlapping intervals in request order after checking each
/// selected folder's available CRCs, including unselected solid siblings. Empty
/// ranges still check data folders. Invalid requests preserve cache and do no I/O.
pub async fn SourceReader::read_ranges(
  self : SourceReader,
  requests : ArrayView[RangeRequest],
) -> Array[Bytes] {
  let archive = self.archive
  ignore(
    bounded(
      requests.length().to_uint64(),
      archive.limits.entries,
      "range requests",
    ),
  )
  let mut remaining = archive.limits.output_bytes
  for request in requests {
    let { id, offset, length, } = request
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
    guard length <= remaining else {
      raise Limit(
        resource="range output bytes",
        maximum=archive.limits.output_bytes,
      )
    }
    remaining -= length
  }
  let groups : Map[Int32, Array[Int32]] = Map([])
  let output = Array::make(requests.length(), b"")
  for index, request in requests {
    if archive.inventory[request.id].block is Some(block) {
      match groups.get(block) {
        Some(indices) => indices.push(index)
        None => groups[block] = [index]
      }
    }
  }
  for block, indices in groups {
    let data = self.load(block)
    for index in indices {
      let request = requests[index]
      let start = self.member_starts[request.id] + request.offset
      output[index] = data[start:start + request.length].to_owned()
    }
  }
  output
}

///|
/// Plan exactly the requested IDs; directory IDs never recursively select
/// children. Preserve request order and metadata, refuse duplicate/colliding
/// paths and unknown file semantics before reading data or staging output.
pub fn SourceArchive::plan_selection(
  self : SourceArchive,
  ids : ArrayView[Int32],
) -> ContentPlan raise ArchiveError {
  ignore(
    bounded(ids.length().to_uint64(), self.limits.entries, "selected entries"),
  )
  let selected : Array[Entry] = []
  for id in ids {
    guard id >= 0 && id < self.inventory.length() else {
      raise NoSuchEntry(id~)
    }
    selected.push(self.inventory[id])
  }
  guard selected.is_empty() || self.file_extensions.is_empty() else {
    raise UnsafePath(
      path="<file metadata>",
      reason="opaque file properties have unknown per-entry semantics; inspect file_properties() and use an explicit import policy",
    )
  }
  plan_entries(selected)
}
