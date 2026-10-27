///|
/// An unrecognized FilesInfo property, preserved in original order. Its bytes
/// may describe the entire file table; no per-entry interpretation is implied.
pub struct FileProperty {
  id : UInt64
  data : Bytes
} derive(Eq, Debug)

///|
pub fn Archive::file_properties(self : Archive) -> Array[FileProperty] {
  self.file_extensions.copy()
}

///|
pub impl ToJson for FileProperty with fn to_json(self) {
  {
    "id": Json(self.id.to_string()),
    "data_base64": Json(@base64.encode(self.data)),
  }
}

///|
pub extend FileProperty with ToJson::{to_json}

///|
#deprecated
pub extend FileProperty with Eq::{equal, not_equal}

///|
#deprecated
pub extend FileProperty with @debug.Debug::{to_repr}

///|
/// Filesystem semantics are inspected as data; exporting them is a separate
/// policy. Original attribute words and member bytes remain available.
pub(all) enum EntrySemantics {
  Regular
  SymbolicLink
  ReparsePoint
  Special
} derive(Eq, Debug)

///|
fn classify_attributes(attributes : UInt32?) -> EntrySemantics {
  guard attributes is Some(value) else { return Regular }
  let mode = if (value & 0x8000U) != 0U { (value >> 16) & 0xf000U } else { 0U }
  if mode == 0xa000U {
    SymbolicLink
  } else if (value & 0x400U) != 0U {
    ReparsePoint
  } else if (value & 0x40U) != 0U ||
    (mode != 0U && mode != 0x8000U && mode != 0x4000U) {
    Special
  } else {
    Regular
  }
}

///|
pub fn Entry::semantics(self : Entry) -> EntrySemantics {
  classify_attributes(self.metadata.attributes)
}

///|
fn EntrySemantics::json_name(self : EntrySemantics) -> String {
  match self {
    Regular => "regular"
    SymbolicLink => "symbolic_link"
    ReparsePoint => "reparse_point"
    Special => "special"
  }
}

///|
#deprecated
pub extend EntrySemantics with Eq::{equal, not_equal}

///|
#deprecated
pub extend EntrySemantics with @debug.Debug::{to_repr}
