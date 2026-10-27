///|
async fn source_volumes_command(
  args : Array[String],
  password : String?,
) -> Bool {
  guard args.get(1) is Some(command) &&
    ["source-volumes-list", "source-volumes-test", "source-volumes-extract"].contains(
      command,
    ) else {
    return false
  }
  let extract = command == "source-volumes-extract"
  guard (extract && args.length() >= 6 && args[2] == "--contents-only") ||
    (!extract && args.length() >= 4 && args[2] == "--json") else {
    fail(
      "usage: source-volumes-list|source-volumes-test --json PART.001 PART.002 ... OR source-volumes-extract --contents-only PARENT NEW_NAME PART.001 PART.002 ...",
    )
  }
  let opened = @host.open_seekable_volumes(
    args[if extract { 5 } else { 3 }:],
    password?,
  )
  defer opened.close()
  if command == "source-volumes-list" {
    println(opened.archive.inventory_json().stringify())
  } else if extract {
    let result = @host.export_source_contents(
      opened.archive,
      parent=args[3],
      name=args[4],
    )
    println(
      "Exported \{result.entries.length()} entries to \{result.directory}; timestamps and attributes were not applied",
    )
  } else {
    println(opened.archive.verify().to_json().stringify())
  }
  true
}
