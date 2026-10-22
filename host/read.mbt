///|
/// Open only regular files, checking their size before allocating input.
/// A file that changes length during reading is rejected.
pub async fn open_file(
  path : String,
  limits~ : @archive.Limits = @archive.Limits::new(),
) -> @archive.Archive {
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
  @archive.Archive::open(bytes, limits~)
}
