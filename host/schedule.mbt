///|
/// Reorder writes, not returned metadata. Group selected files by folder so
/// each folder is decoded at most once. Unstreamed empty files need no cache.
/// Archive.open has already bounded the sum of all folder/member sizes.
fn export_schedule(
  archive : @archive.Archive,
  selected : ArrayView[@archive.Entry],
) -> (Array[@archive.Entry], Int32) {
  let groups : Map[Int32, Array[@archive.Entry]] = Map([])
  let empty : Array[@archive.Entry] = []
  for entry in selected {
    if entry.kind == File {
      match entry.block {
        Some(id) =>
          match groups.get(id) {
            Some(entries) => entries.push(entry)
            None => groups[id] = [entry]
          }
        None => empty.push(entry)
      }
    }
  }
  let sizes : Map[Int32, Int32] = Map([])
  for entry in archive.entries() {
    if entry.block is Some(id) && groups.contains(id) {
      sizes[id] = sizes.get(id).unwrap_or(0) + entry.size
    }
  }
  let ordered : Array[@archive.Entry] = []
  let mut cache_bytes = 0
  for id, entries in groups {
    cache_bytes = cache_bytes.max(sizes.get(id).unwrap_or(0))
    for entry in entries {
      ordered.push(entry)
    }
  }
  for entry in empty {
    ordered.push(entry)
  }
  (ordered, cache_bytes)
}
