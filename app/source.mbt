///|
async fn source_command(args : Array[String], password : String?) -> Bool {
  guard args.get(1) is Some(command) &&
    [
      "source-list", "source-test", "source-audit", "source-read", "source-read-range",
      "source-extract", "source-extract-selected",
    ].contains(command) else {
    return false
  }
  let json = command == "source-list" ||
    command == "source-test" ||
    command == "source-audit"
  let extract = command == "source-extract"
  let selected = command == "source-extract-selected"
  guard (json && args.length() == 4 && args[2] == "--json") ||
    (extract && args.length() == 6 && args[2] == "--contents-only") ||
    (selected && args.length() >= 7 && args[2] == "--contents-only") ||
    (command == "source-read" && args.length() == 4) ||
    (command == "source-read-range" && args.length() == 6) else {
    fail(
      "usage: source-list|source-test|source-audit --json FILE OR source-read FILE ID OR source-read-range FILE ID OFFSET LENGTH OR source-extract --contents-only FILE PARENT NEW_NAME OR source-extract-selected --contents-only FILE PARENT NEW_NAME ID...",
    )
  }
  let opened = @host.open_seekable_file(
    args[if json || extract || selected { 3 } else { 2 }],
    password?,
  )
  defer opened.close()
  if command == "source-list" {
    println(opened.archive.inventory_json().stringify())
  } else if command == "source-test" {
    println(opened.archive.verify().to_json().stringify())
  } else if command == "source-audit" {
    println(opened.archive.audit().to_json().stringify())
  } else if selected {
    let ids = args[6:].map(id => @string.parse_int(id))
    let output = @host.export_source_selected(
      opened.archive,
      ids[:],
      parent=args[4],
      name=args[5],
    )
    println(
      "Exported \{output.entries.length()} selected entries to \{output.directory}; unselected folders were not verified and metadata was not applied",
    )
  } else if extract {
    let output = @host.export_source_contents(
      opened.archive,
      parent=args[4],
      name=args[5],
    )
    println(
      "Exported \{output.entries.length()} entries to \{output.directory}; timestamps and attributes were not applied",
    )
  } else {
    let reader = opened.archive.reader()
    let id = @string.parse_int(args[3])
    let bytes = if command == "source-read" {
      reader.read(id).bytes
    } else {
      reader.read_range(
        id,
        offset=@string.parse_int(args[4]),
        length=@string.parse_int(args[5]),
      )
    }
    @stdio.stdout.write(bytes)
    @stdio.stderr.write(
      "Only the selected folder was checked; use source-test for whole-archive verification.\n",
    )
  }
  true
}
