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
  publish_contents(plan, items, parent~, name~)
}

///|
/// Export exactly these stable member IDs, with necessary parents. Selecting
/// a directory does not select descendants. Only selected folders are decoded;
/// all CRCs in those folders, including unselected solid siblings, are checked.
/// Unselected folders are not verified. Publication and metadata contracts are
/// the same as export_contents. Repeated IDs and selected path aliases fail
/// before staging. An empty selection deliberately creates an empty directory.
pub async fn export_selected(
  archive : @archive.Archive,
  ids : ArrayView[Int32],
  parent~ : String,
  name~ : String,
) -> ExportedContents {
  @archive.validate_path(name)
  guard !name.contains("/") else {
    fail("export name must be a single directory component")
  }
  let plan = archive.plan_selection(ids)
  let items = archive.reader(cache_bytes=0).read_many(ids)
  publish_contents(plan, items, parent~, name~)
}

///|
async fn publish_contents(
  plan : @archive.ContentPlan,
  items : Array[@archive.Member],
  parent~ : String,
  name~ : String,
) -> ExportedContents {
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
