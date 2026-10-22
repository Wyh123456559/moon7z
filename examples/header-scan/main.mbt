///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    fail("usage: moon run examples/header-scan -- archive.7z")
  }
  let archive = @host.open_file(args[1])
  let files = archive.entries().filter(entry => entry.kind == File)
  let requests = files.map(entry => {
    @archive.RangeRequest::new(
      entry.id,
      offset=0,
      length=if entry.size < 16 { entry.size } else { 16 },
    )
  })
  let reader = archive.reader(cache_bytes=0)
  let prefixes = reader.read_ranges(requests)
  for i, prefix in prefixes {
    println("\{files[i].id}\t\{Repr(files[i].name)}\t\{Repr(prefix)}")
  }
  println("Decode attempts: \{reader.stats().decode_attempts}")
}
