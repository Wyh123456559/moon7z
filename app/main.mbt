///|
async fn main {
  let args = @env.args()
  if args.length() == 5 && args[1] == "diff" && args[2] == "--json" {
    let left = @host.open_file(args[3])
    let right = @host.open_file(args[4])
    println(left.compare(right).to_json().stringify())
    return
  }
  if args.length() >= 7 &&
    args[1] == "extract-selected" &&
    args[2] == "--contents-only" {
    let archive = @host.open_file(args[3])
    let ids = args[6:].map(id => @string.parse_int(id))
    let exported = @host.export_selected(
      archive,
      ids,
      parent=args[4],
      name=args[5],
    )
    println(
      "Exported \{exported.entries.length()} selected entries to \{exported.directory}; only selected folders were verified and metadata was not applied",
    )
    return
  }
  if args.length() >= 3 &&
    (args[1] == "list" || args[1] == "test") &&
    args[2] == "--json" {
    let strict = args.length() == 5 &&
      args[1] == "test" &&
      args[3] == "--require-member-crcs"
    guard args.length() == 4 || strict else {
      fail(
        "usage: list --json archive.7z OR test --json [--require-member-crcs] archive.7z",
      )
    }
    let archive = @host.open_file(args[if strict { 4 } else { 3 }])
    let document = if args[1] == "list" {
      archive.inventory_json()
    } else {
      archive.verify(require_member_crcs=strict).to_json()
    }
    println(document.stringify())
    return
  }
  if args.length() == 4 &&
    args[1] == "test" &&
    args[2] == "--require-member-crcs" {
    let archive = @host.open_file(args[3])
    let report = archive.verify(require_member_crcs=true) catch {
      err => fail(err.to_string())
    }
    println(Repr(report))
    return
  }
  if args.length() == 6 && args[1] == "read-range" {
    let archive = @host.open_file(args[2])
    let id = @string.parse_int(args[3])
    let offset = @string.parse_int(args[4])
    let length = @string.parse_int(args[5])
    let bytes = archive.reader().read_range(id, offset~, length~)
    @stdio.stdout.write(bytes)
    return
  }
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
      "usage: moon run app -- <list|test> [--json] archive.7z OR diff --json left.7z right.7z OR test [--json] --require-member-crcs archive.7z OR read archive.7z entry-id OR read-range archive.7z entry-id offset length OR extract --contents-only archive.7z existing-parent new-name OR extract-selected --contents-only archive.7z existing-parent new-name entry-id...",
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
