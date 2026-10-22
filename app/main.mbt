///|
async fn main {
  let args = @env.args()
  guard args.length() == 3 && (args[1] == "list" || args[1] == "test") else {
    fail("usage: moon run app -- <list|test> archive.7z")
  }
  let archive = @host.open_file(args[2])
  if args[1] == "list" {
    for entry in archive.entries() {
      println(
        "\{entry.id}\t\{entry.size}\t\{Repr(entry.kind)}\t\{Repr(entry.name)}",
      )
    }
  } else {
    let report = archive.verify() catch { err => fail("\{Repr(err)}") }
    println(Repr(report))
  }
}
