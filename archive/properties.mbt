///|
/// Opaque archive-level metadata, retained in original order, including
/// repeated IDs and empty values. Its semantics are not applied to extraction.
pub struct ArchiveProperty {
  id : UInt64
  data : Bytes
} derive(Eq, Debug)

///|
/// Return detached metadata records. Immutable Bytes preserve arbitrary values.
/// ```mbt check
/// test {
///   let empty = b"7z\xbc\xaf\x27\x1c\x00\x04\x8d\x9b\xd5\x0f" + b"\x00".repeat(20)
///   let archive = @archive.Archive::open(empty)
///   assert_true(archive.properties().is_empty())
/// }
/// ```
pub fn Archive::properties(self : Archive) -> Array[ArchiveProperty] {
  self.archive_properties.copy()
}

///|
fn read_archive_properties(
  r : Cursor,
  limits : Limits,
) -> Array[ArchiveProperty] raise ArchiveError {
  let result : Array[ArchiveProperty] = []
  for ;; {
    let id = r.number()
    if id == 0UL {
      break
    }
    ignore(
      bounded(
        (result.length() + 1).to_uint64(),
        limits.entries,
        "archive property records",
      ),
    )
    let data = r.take(r.count(limits.header_bytes, "archive property bytes"))
    result.push({ id, data, })
  }
  result
}

///|
pub impl ToJson for ArchiveProperty with fn to_json(self) {
  {
    "id": Json(self.id.to_string()),
    "data_base64": Json(@base64.encode(self.data)),
  }
}

///|
pub extend ArchiveProperty with ToJson::{to_json}

///|
#deprecated
pub extend ArchiveProperty with Eq::{equal, not_equal}

///|
#deprecated
pub extend ArchiveProperty with @debug.Debug::{to_repr}
