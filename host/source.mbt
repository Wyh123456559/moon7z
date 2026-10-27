///|
/// Owns an open regular file backing the source archive. Close after all reads
/// finish. A closed source refuses further I/O; cached member bytes may remain
/// available until their SourceReader is cleared or dropped.
pub struct SourceFile {
  archive : @archive.SourceArchive
  priv owner : SourceHandle
}

///|
priv struct SourceFileState {
  mut closed : Bool
}

///|
pub fn SourceFile::close(self : SourceFile) -> Unit {
  self.owner.close()
}

///|
priv struct SourceHandle {
  source : @archive.SeekableInput
  files : Array[@fs.File]
  state : SourceFileState
}

///|
fn SourceHandle::close(self : SourceHandle) -> Unit {
  if !self.state.closed {
    self.state.closed = true
    for file in self.files {
      file.close()
    }
  }
}

///|
/// Read metadata through positioned I/O; main packed folders are fetched only
/// when a SourceReader or verify requests them. Host offsets are limited to the
/// platform file API's nonnegative Int64 range, with no Int32 narrowing.
pub async fn open_seekable_file(
  path : String,
  limits~ : @archive.Limits = @archive.Limits::new(),
  max_source_bytes~ : UInt64 = 1099511627776UL,
  max_output_bytes~ : UInt64 = 17179869184UL,
  password? : String,
) -> SourceFile {
  open_source_files(
    [path],
    limits~,
    max_source_bytes~,
    max_output_bytes~,
    password~,
    max_parts=1,
  )
}

///|
/// Open explicitly ordered numeric volumes with UInt64 logical positions.
/// Parts are composed as positioned sources and are never concatenated in RAM.
pub async fn open_seekable_volumes(
  paths : ArrayView[String],
  limits~ : @archive.Limits = @archive.Limits::new(),
  max_source_bytes~ : UInt64 = 1099511627776UL,
  max_output_bytes~ : UInt64 = 17179869184UL,
  max_volumes~ : Int32 = 1024,
  password? : String,
) -> SourceFile {
  ignore(@archive.VolumeSequence::new(volume_names(paths)[:], max_volumes~))
  open_source_files(
    paths,
    limits~,
    max_source_bytes~,
    max_output_bytes~,
    password~,
    max_parts=max_volumes,
  )
}

///|
async fn open_source_files(
  paths : ArrayView[String],
  limits~ : @archive.Limits,
  max_source_bytes~ : UInt64,
  max_output_bytes~ : UInt64,
  password~ : String?,
  max_parts~ : Int32,
) -> SourceFile {
  let owner = open_source_handle(paths, max_source_bytes~, max_parts~)
  let mut opened = false
  defer (if !opened { owner.close() })
  let archive = @archive.SourceArchive::open(
    owner.source,
    limits~,
    max_source_bytes~,
    max_output_bytes~,
    password?,
  )
  opened = true
  { archive, owner, }
}

///|
async fn open_source_handle(
  paths : ArrayView[String],
  max_source_bytes~ : UInt64,
  max_parts~ : Int32,
) -> SourceHandle {
  let files : Array[@fs.File] = []
  let inputs : Array[@archive.SeekableInput] = []
  let state = { closed: false, }
  let mut opened = false
  defer (if !opened {
    for file in files {
      file.close()
    }
  })
  let mut total = 0UL
  for path in paths {
    let file = @fs.open(path, mode=ReadOnly)
    files.push(file)
    guard file.kind() == Regular else {
      fail("seekable archive input must be a regular file")
    }
    let size = file.size()
    guard size >= 0L else {
      fail("seekable input size is not representable by the host file API")
    }
    guard paths.length() == 1 || size > 0L else {
      fail("seekable volume \{path} is empty")
    }
    guard size.reinterpret_as_uint64() <= max_source_bytes - total else {
      fail(
        "combined seekable source exceeds max_source_bytes=\{max_source_bytes}",
      )
    }
    total += size.reinterpret_as_uint64()
    let source = @archive.SeekableInput::new(size.reinterpret_as_uint64(), async fn(
      offset,
      length,
    ) {
      guard !state.closed else {
        fail("seekable source file is closed; reopen it before further reads")
      }
      guard file.size() == size else {
        fail("seekable input changed length; reopen a stable completed file")
      }
      let bytes = file.read_exactly_at(
        length,
        position=offset.reinterpret_as_int64(),
      )
      guard file.size() == size else {
        fail(
          "seekable input changed length during reading; retry a stable file",
        )
      }
      bytes
    })
    inputs.push(source)
  }
  let source = @archive.SeekableInput::concat(inputs[:], max_parts~)
  opened = true
  { source, files, state, }
}
