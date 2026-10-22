///|
/// A file interval; requests are validated against the archive before decoding.
pub struct RangeRequest {
  id : Int32
  offset : Int32
  length : Int32
} derive(Eq, Debug)

///|
pub fn RangeRequest::new(
  id : Int32,
  offset~ : Int32,
  length~ : Int32,
) -> RangeRequest {
  { id, offset, length, }
}

///|
#deprecated
pub extend RangeRequest with Eq::{equal, not_equal}

///|
#deprecated
pub extend RangeRequest with @debug.Debug::{to_repr}

///|
/// Read intervals in request order, including duplicate and overlapping ranges.
/// Count and combined byte length are bounded by Limits.entries/output_bytes.
/// Every request is checked before any decode/cache change. Each selected
/// folder is decoded at most once per call, even with caching disabled. Empty
/// ranges in data folders still verify all their available sibling CRCs.
pub fn Reader::read_ranges(
  self : Reader,
  requests : ArrayView[RangeRequest],
) -> Array[Bytes] raise ArchiveError {
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
    guard id >= 0 && id < archive.inventory.length() else {
      raise NoSuchEntry(id~)
    }
    let entry = archive.inventory[id]
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
