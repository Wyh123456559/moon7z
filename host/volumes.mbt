///|
/// Read an explicit ordered list of numeric split files. Every regular-file
/// size and the cumulative budget are checked before reading any payload.
/// Open handles are always closed, including on missing parts or decode failure.
pub async fn open_volume_files(
  paths : ArrayView[String],
  limits~ : @archive.Limits = @archive.Limits::new(),
  password? : String,
  max_volumes~ : Int32 = 1024,
) -> @archive.SplitArchive {
  let names = paths.map(path => {
    let unix = if @async.platform is Windows {
      path.split("\\").to_array().last().unwrap().to_owned()
    } else {
      path
    }
    unix.split("/").to_array().last().unwrap().to_owned()
  })
  let sequence = @archive.VolumeSequence::new(names[:], max_volumes~)
  guard limits.input_bytes >= 0 && limits.input_bytes <= 0x3fffffff else {
    fail("combined volume input limit must be between zero and 1073741823")
  }
  let files : Array[@fs.File] = []
  defer (for file in files {
    file.close()
  })
  let sizes : Array[Int32] = []
  let mut total = 0L
  for i, path in paths {
    let file = @fs.open(path, mode=ReadOnly) catch {
      err =>
        fail(
          "cannot open volume index \{i} at \{path}: \{err}; check missing volumes and permissions",
        )
    }
    files.push(file)
    guard file.kind() == Regular else {
      fail("volume index \{i} at \{path} must be a regular file")
    }
    let size = file.size()
    guard size > 0L else { fail("volume index \{i} at \{path} is empty") }
    guard size <= limits.input_bytes.to_int64() - total else {
      fail(
        "combined volume input exceeds the configured \{limits.input_bytes}-byte limit at \{path}",
      )
    }
    sizes.push(size.to_int())
    total += size
  }
  let parts : Array[Bytes] = []
  for i, file in files {
    let bytes = file.read_exactly(sizes[i]) catch {
      err =>
        fail(
          "cannot read complete volume \{paths[i]}: \{err}; retry a completed stable volume set",
        )
    }
    guard file.read_some(max_len=1) is None &&
      file.size() == sizes[i].to_int64() else {
      fail(
        "volume \{paths[i]} changed length during reading; retry a completed stable volume set",
      )
    }
    parts.push(bytes)
  }
  sequence.open(parts[:], limits~, password?)
}
