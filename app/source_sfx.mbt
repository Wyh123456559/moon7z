///|
async fn source_sfx_command(
  original : Array[String],
  password : String?,
) -> Bool {
  guard original.get(1) is Some(command) &&
    [
      "source-sfx-list", "source-sfx-test", "source-sfx-read", "source-sfx-read-range",
      "source-sfx-extract", "source-sfx-volumes-list", "source-sfx-volumes-test",
      "source-sfx-volumes-extract",
    ].contains(command) else {
    return false
  }
  let mut args = original
  let mut offset : UInt64? = None
  let mut search_bytes = 1048576UL
  if args.get(2) is Some(option) &&
    ["--scan-bytes", "--offset"].contains(option) {
    guard args.get(3) is Some(value) else {
      fail("--scan-bytes/--offset requires a UInt64 decimal value")
    }
    let number = @string.parse_uint64(value)
    if option == "--offset" {
      offset = Some(number)
    } else {
      search_bytes = number
    }
    args = args[:2].to_owned() + args[4:].to_owned()
  }
  let volumes = command.has_prefix("source-sfx-volumes-")
  let listing = command.has_suffix("-list")
  let testing = command.has_suffix("-test")
  let extraction = command.has_suffix("-extract")
  guard (
      (listing || testing) &&
      args.length() >= 4 &&
      args[2] == "--json" &&
      (if volumes { args.length() >= 4 } else { args.length() == 4 })
    ) ||
    (
      extraction &&
      args.length() >= 6 &&
      args[2] == "--contents-only" &&
      (if volumes { args.length() >= 6 } else { args.length() == 6 })
    ) ||
    (command == "source-sfx-read" && args.length() == 4) ||
    (command == "source-sfx-read-range" && args.length() == 6) else {
    fail(
      "usage: source-sfx-list|source-sfx-test [--scan-bytes N|--offset N] --json FILE; source-sfx-read FILE ID; source-sfx-read-range FILE ID OFFSET LENGTH; source-sfx-extract --contents-only FILE PARENT NEW_NAME; source-sfx-volumes-list|test --json PART...; source-sfx-volumes-extract --contents-only PARENT NEW_NAME PART...",
    )
  }
  let opened = if volumes {
    @host.open_seekable_sfx_volumes(
      args[if extraction { 5 } else { 3 }:],
      password?,
      offset?,
      search_bytes~,
    )
  } else {
    @host.open_seekable_sfx_file(
      args[if listing || testing || extraction { 3 } else { 2 }],
      password?,
      offset?,
      search_bytes~,
    )
  }
  defer opened.close()
  let embedded = opened.embedded
  if listing {
    println(embedded.inventory_json().stringify())
  } else if testing {
    let report = embedded.archive.verify()
    let json : Json = {
      "schema": "moon7z.source_embedded_verification.v1",
      "envelope_verified": false,
      "offset": Json(embedded.offset.to_string()),
      "archive_bytes": Json(embedded.payload.size.to_string()),
      "suffix_bytes": Json(embedded.suffix.size.to_string()),
      "verification": report.to_json(),
    }
    println(json.stringify())
  } else if extraction {
    let result = @host.export_source_contents(
      embedded.archive,
      parent=args[if volumes { 3 } else { 4 }],
      name=args[if volumes { 4 } else { 5 }],
    )
    println(
      "Exported \{result.entries.length()} entries to \{result.directory}; prefix (\{embedded.prefix.size} bytes), suffix (\{embedded.suffix.size} bytes), timestamps and attributes were not applied; original inputs are unchanged",
    )
  } else {
    let reader = embedded.archive.reader()
    let id = @string.parse_int(args[3])
    let bytes = if command == "source-sfx-read" {
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
      "Only the selected archive folder was checked; the envelope was not authenticated.\n",
    )
  }
  true
}
