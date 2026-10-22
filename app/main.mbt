///|
async fn main {
  let args = @env.args()
  if args.length() == 4 && args[1] == "read" {
    let archive = @host.open_file(args[2])
    let id = @string.parse_int(args[3])
    let item = archive.reader().read(id)
    guard item.entry.kind == File else {
      fail("selected entry is a directory; select a file ID")
    }
    @stdio.stdout.write(item.bytes)
    return
  }
  if args.length() == 6 && args[1] == "extract" && args[2] == "--contents-only" {
    let archive = @host.open_file(args[3])
    let exported = @host.export_contents(archive, parent=args[4], name=args[5])
    println(
      "Exported \{exported.entries.length()} entries to \{exported.directory}; timestamps and attributes were not applied",
    )
    return
  }
  guard args.length() == 3 && (args[1] == "list" || args[1] == "test") else {
    fail(
      "usage: moon run app -- <list|test> archive.7z OR read archive.7z entry-id OR extract --contents-only archive.7z existing-parent new-name",
    )
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
