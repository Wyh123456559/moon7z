///|
async fn volume_command(args : Array[String], password : String?) -> Bool {
  guard args.get(1) is Some(command) &&
    ["volumes-list", "volumes-test", "volumes-extract"].contains(command) else {
    return false
  }
  let extraction = command == "volumes-extract"
  guard (extraction && args.length() >= 6 && args[2] == "--contents-only") ||
    (!extraction && args.length() >= 4 && args[2] == "--json") else {
    fail(
      "usage: volumes-list|volumes-test --json PART.001 PART.002 ... OR volumes-extract --contents-only EXISTING_PARENT NEW_NAME PART.001 PART.002 ...; supply every part in numeric order",
    )
  }
  let paths = args[if extraction { 5 } else { 3 }:]
  let split = @host.open_volume_files(paths, password?)
  if command == "volumes-list" {
    println(split.inventory_json().stringify())
  } else if command == "volumes-test" {
    let report = split.archive.verify()
    let json : Json = {
      "schema": "moon7z.split_verification.v1",
      "volume_count": Json(split.volumes().length()),
      "verification": report.to_json(),
    }
    println(json.stringify())
  } else {
    let exported = @host.export_contents(
      split.archive,
      parent=args[3],
      name=args[4],
    )
    println(
      "Exported \{exported.entries.length()} entries from \{split.volumes().length()} volumes to \{exported.directory}; timestamps and attributes were not applied",
    )
  }
  true
}
