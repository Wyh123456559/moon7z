///|
async fn sfx_command(original : Array[String], password : String?) -> Bool {
  guard original.get(1) is Some(command) &&
    ["sfx-list", "sfx-test", "sfx-extract"].contains(command) else {
    return false
  }
  let mut args = original
  let search_bytes = if args.get(2) == Some("--scan-bytes") {
    guard args.length() >= 4 else {
      fail("--scan-bytes requires a nonnegative integer")
    }
    let value = @string.parse_int(args[3])
    args = args[:2].to_owned() + args[4:].to_owned()
    value
  } else {
    1024 * 1024
  }
  let extraction = command == "sfx-extract"
  guard (extraction && args.length() == 6 && args[2] == "--contents-only") ||
    (!extraction && args.length() == 4 && args[2] == "--json") else {
    fail(
      "usage: sfx-list|sfx-test [--scan-bytes N] --json FILE OR sfx-extract [--scan-bytes N] --contents-only FILE EXISTING_PARENT NEW_NAME",
    )
  }
  let embedded = @host.open_embedded_file(args[3], password?, search_bytes~)
  if command == "sfx-list" {
    println(embedded.inventory_json().stringify())
  } else if command == "sfx-test" {
    let report = embedded.archive.verify()
    let document : Json = {
      "schema": "moon7z.embedded_verification.v1",
      "envelope_verified": false,
      "offset": Json(embedded.prefix.length()),
      "archive_bytes": Json(embedded.payload.length()),
      "suffix_bytes": Json(embedded.suffix.length()),
      "verification": report.to_json(),
    }
    println(document.stringify())
  } else {
    let exported = @host.export_contents(
      embedded.archive,
      parent=args[4],
      name=args[5],
    )
    println(
      "Exported \{exported.entries.length()} entries to \{exported.directory}; the executable/configuration prefix (\{embedded.prefix.length()} bytes), suffix (\{embedded.suffix.length()} bytes), timestamps and attributes were not applied. Original input is unchanged.",
    )
  }
  true
}
