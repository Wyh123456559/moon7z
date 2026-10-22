///|
/// Original metadata is returned, rather than silently claiming to restore
/// timestamps, permissions or filesystem attributes.
pub struct ExportedContents {
  directory : String
  entries : Array[@archive.Entry]
}

///|
async fn staging_directory(parent : String) -> String {
  let random = @random.Rand()
  for _ in 0..<16 {
    let path = parent + "/.moon7z-" + random.uint64().to_string(radix=16)
    try @fs.mkdir(path, permission=0o700) catch {
      @os_error.OSError(_) as err if err.is_EEXIST() => ()
      err => raise err
    } noraise {
      _ => return path
    }
  }
  fail("cannot reserve a new staging directory in the export parent")
}

///|
/// Export verified file contents into a new child of an existing, trusted
/// parent. Original metadata is returned without applying it to disk. An
/// existing destination, including an empty directory, is never replaced.
/// The caller must exclusively control the parent and staging directory while
/// this operation runs; this is not a sandbox against a hostile local writer.
pub async fn export_contents(
  archive : @archive.Archive,
  parent~ : String,
  name~ : String,
) -> ExportedContents {
  @archive.validate_path(name)
  guard !name.contains("/") else {
    fail("export name must be a single directory component")
  }
  let plan = archive.plan_contents()
  let items = archive.extract_all()
  let parent = @fs.realpath(parent)
  guard @fs.kind(parent, follow_symlink=false) == Directory else {
    fail("export parent must be an existing directory")
  }
  let destination = parent + "/" + name
  let staging = staging_directory(parent)
  let mut published = false
  defer (if !published { @fs.rmdir(staging, recursive=true) })
  for directory in plan.directories() {
    @fs.mkdir(staging + "/" + directory, permission=0o700)
  }
  for item in items {
    if item.entry.kind == File {
      @fs.write_file(
        staging + "/" + item.entry.name,
        item.bytes,
        create_mode=CreateNew,
        permission=0o600,
      )
    }
  }
  @fs.rename(staging, destination, replace=false)
  published = true
  { directory: destination, entries: plan.entries(), }
}
