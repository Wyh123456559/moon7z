///|
/// Open only regular files, checking their size before allocating input.
/// A file that changes length during reading is rejected.
pub async fn open_file(
  path : String,
  limits~ : @archive.Limits = @archive.Limits::new(),
  password? : String,
) -> @archive.Archive {
  @archive.Archive::open(read_input_file(path, limits~), limits~, password?)
}

///|
/// Inspect/import an SFX or another embedded archive without running its stub.
/// The original prefix/payload/suffix are returned intact and remain bounded
/// by the same whole-input size policy as ordinary file opening.
pub async fn open_embedded_file(
  path : String,
  limits~ : @archive.Limits = @archive.Limits::new(),
  password? : String,
  search_bytes~ : Int32 = 1024 * 1024,
) -> @archive.EmbeddedArchive {
  @archive.EmbeddedArchive::open(
    read_input_file(path, limits~),
    limits~,
    password?,
    search_bytes~,
  )
}

///|
async fn read_input_file(path : String, limits~ : @archive.Limits) -> Bytes {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.kind() == Regular else {
    fail("archive input must be a regular file")
  }
  let size = file.size()
  guard limits.input_bytes >= 0 &&
    limits.input_bytes <= 0x3fffffff &&
    size >= 0L &&
    size <= limits.input_bytes.to_int64() else {
    fail(
      "archive input exceeds the configured \{limits.input_bytes}-byte limit",
    )
  }
  let bytes = file.read_exactly(size.to_int())
  guard file.read_some(max_len=1) is None else {
    fail("archive input grew while being read; retry from a stable file")
  }
  bytes
}
