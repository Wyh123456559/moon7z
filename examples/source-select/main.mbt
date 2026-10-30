///|
async fn main {
  let args = @env.args()
  guard args.length() >= 5 else {
    fail("usage: source-select FILE EXISTING_PARENT NEW_NAME ID...")
  }
  let opened = @host.open_seekable_file(args[1])
  defer opened.close()
  let ids = args[4:].map(id => @string.parse_int(id))
  let requests = ids.map(id => {
    @archive.RangeRequest::new(id, offset=0, length=0)
  })
  let reader = opened.archive.reader(cache_bytes=0)
  let previews = reader.read_ranges(requests[:])
  assert_true(previews.all(bytes => bytes.is_empty()))
  let exported = @host.export_source_selected(
    opened.archive,
    ids[:],
    parent=args[2],
    name=args[3],
  )
  println(
    "Exported \{exported.entries.length()} selected files after checking their folders; unselected folders were not verified",
  )
}
