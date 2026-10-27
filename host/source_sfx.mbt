///|
/// Owns the file handles backing an SFX and its exact envelope views.
pub struct SourceSfxFile {
  embedded : @archive.SourceEmbeddedArchive
  priv owner : SourceHandle
}

///|
pub fn SourceSfxFile::close(self : SourceSfxFile) -> Unit {
  self.owner.close()
}

///|
/// Discover a CRC-valid start header through bounded reads. An explicit offset
/// bypasses discovery; search_bytes applies only when no offset is supplied.
pub async fn open_seekable_sfx_file(
  path : String,
  limits~ : @archive.Limits = @archive.Limits::new(),
  max_source_bytes~ : UInt64 = 1099511627776UL,
  max_output_bytes~ : UInt64 = 17179869184UL,
  search_bytes~ : UInt64 = 1048576UL,
  offset? : UInt64,
  password? : String,
) -> SourceSfxFile {
  open_source_sfx(
    [path],
    limits~,
    max_source_bytes~,
    max_output_bytes~,
    search_bytes~,
    offset~,
    password~,
    max_parts=1,
  )
}

///|
/// Open a numeric split SFX as one logical source, preserving envelope views
/// across volume boundaries without concatenating complete inputs in memory.
pub async fn open_seekable_sfx_volumes(
  paths : ArrayView[String],
  limits~ : @archive.Limits = @archive.Limits::new(),
  max_source_bytes~ : UInt64 = 1099511627776UL,
  max_output_bytes~ : UInt64 = 17179869184UL,
  search_bytes~ : UInt64 = 1048576UL,
  offset? : UInt64,
  max_volumes~ : Int32 = 1024,
  password? : String,
) -> SourceSfxFile {
  ignore(@archive.VolumeSequence::new(volume_names(paths)[:], max_volumes~))
  open_source_sfx(
    paths,
    limits~,
    max_source_bytes~,
    max_output_bytes~,
    search_bytes~,
    offset~,
    password~,
    max_parts=max_volumes,
  )
}

///|
async fn open_source_sfx(
  paths : ArrayView[String],
  limits~ : @archive.Limits,
  max_source_bytes~ : UInt64,
  max_output_bytes~ : UInt64,
  search_bytes~ : UInt64,
  offset~ : UInt64?,
  password~ : String?,
  max_parts~ : Int32,
) -> SourceSfxFile {
  let owner = open_source_handle(paths, max_source_bytes~, max_parts~)
  let mut opened = false
  defer (if !opened { owner.close() })
  let embedded = match offset {
    Some(offset) =>
      @archive.SourceEmbeddedArchive::open_at(
        owner.source,
        offset,
        limits~,
        max_source_bytes~,
        max_output_bytes~,
        password?,
      )
    None =>
      @archive.SourceEmbeddedArchive::open(
        owner.source,
        limits~,
        max_source_bytes~,
        max_output_bytes~,
        search_bytes~,
        password?,
      )
  }
  opened = true
  { embedded, owner, }
}
