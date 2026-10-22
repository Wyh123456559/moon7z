///|
/// Errors identify an input defect, unsupported feature or resource policy.
pub suberror ArchiveError {
  Invalid(offset~ : Int32, reason~ : String)
  Unsupported(feature~ : String)
  Limit(resource~ : String, maximum~ : Int32)
  Checksum(scope~ : String)
  Codec(reason~ : String)
  UnsafePath(path~ : String, reason~ : String)
  NoSuchEntry(id~ : Int32)
} derive(Debug)

///|
/// Limits apply before allocating or decoding archive-controlled sizes.
pub struct Limits {
  input_bytes : Int32
  header_bytes : Int32
  output_bytes : Int32
  dictionary_bytes : Int32
  entries : Int32
} derive(Debug, Eq)

///|
/// The result is an owned in-memory import, not a filesystem restoration.
pub(all) enum EntryKind {
  File
  Directory
} derive(Debug, Eq)

///|
/// Optional timestamps are raw 100-nanosecond Windows FILETIME values.
pub struct Metadata {
  created : UInt64?
  accessed : UInt64?
  modified : UInt64?
  attributes : UInt32?
} derive(Debug, Eq)

///|
/// Stable IDs preserve archive order, including repeated original names.
pub struct Entry {
  id : Int32
  name : String
  kind : EntryKind
  size : Int32
  crc32 : UInt32?
  block : Int32?
  metadata : Metadata
} derive(Debug, Eq)

///|
/// A member is returned after the checks for its decoded folder have passed.
/// `extract_all` verifies the entire archive; a Reader checks selected folders.
pub struct Member {
  entry : Entry
  bytes : Bytes
} derive(Debug, Eq)

///|
/// Missing CRCs are counted explicitly and are never reported as verified.
pub struct Verification {
  files : Int32
  bytes : Int32
  blocks : Int32
  member_crcs_checked : Int32
  members_without_crc : Int32
} derive(Debug, Eq)

///|
pub fn Limits::new(
  input_bytes~ : Int32 = 64 * 1024 * 1024,
  header_bytes~ : Int32 = 4 * 1024 * 1024,
  output_bytes~ : Int32 = 128 * 1024 * 1024,
  dictionary_bytes~ : Int32 = 64 * 1024 * 1024,
  entries~ : Int32 = 10000,
) -> Limits {
  { input_bytes, header_bytes, output_bytes, dictionary_bytes, entries, }
}

///|
priv struct Coder {
  codec_id : Bytes
  properties : Bytes
}

///|
priv struct Block {
  coders : Array[Coder]
  mut size : Int32
  mut crc : UInt32?
  pieces : Array[(Int32, UInt32?)]
}

///|
priv struct Streams {
  pack_offset : Int32
  pack_sizes : Array[Int32]
  pack_crcs : Array[UInt32?]
  blocks : Array[Block]
}

///|
/// Opening validates headers and the complete member-to-block mapping.
/// Data CRCs are checked by `verify` and `extract_all`, not by listing.
pub struct Archive {
  priv input : Bytes
  priv limits : Limits
  priv streams : Streams
  priv inventory : Array[Entry]
}

///|
/// Return a fresh inventory array; callers cannot alter extraction mappings.
pub fn Archive::entries(self : Archive) -> Array[Entry] {
  self.inventory.copy()
}

///|
#deprecated
pub extend Limits with Eq::{equal, not_equal}

///|
#deprecated
pub extend EntryKind with Eq::{equal, not_equal}

///|
#deprecated
pub extend Metadata with Eq::{equal, not_equal}

///|
#deprecated
pub extend Entry with Eq::{equal, not_equal}

///|
#deprecated
pub extend Member with Eq::{equal, not_equal}

///|
#deprecated
pub extend Verification with Eq::{equal, not_equal}

///|
#deprecated
pub extend ArchiveError with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Limits with @debug.Debug::{to_repr}

///|
#deprecated
pub extend EntryKind with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Metadata with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Entry with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Member with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Verification with @debug.Debug::{to_repr}
