///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    fail("usage: moon run examples/preview -- archive.7z")
  }
  let archive = @host.open_file(args[1])
  let reader = archive.reader()
  let ids = archive
    .entries()
    .filter(entry => entry.kind == File && entry.name.has_suffix(".json"))
    .map(entry => entry.id)
  for item in reader.read_many(ids) {
    println("\{item.entry.name}: \{@utf8.decode(item.bytes)}")
  }
  if ids.get(0) is Some(id) {
    ignore(reader.read(id))
  }
  println("Reader counters: \{Repr(reader.stats())}")
  println(
    "Only selected folders were verified. Run the test command for whole-archive verification.",
  )
}
