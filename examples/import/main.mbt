///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    fail("usage: moon run examples/import -- archive.7z")
  }
  let archive = @host.open_file(args[1])
  let items = archive.extract_all()
  let mut imported = 0
  for item in items {
    if item.entry.kind == File && item.entry.name.has_suffix(".json") {
      let document = @json.parse(@utf8.decode(item.bytes))
      println("\{item.entry.name}: \{document.stringify()}")
      imported += 1
    }
  }
  println("Imported \{imported} JSON documents after archive verification")
}
