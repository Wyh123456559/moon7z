///|
async fn source_compare_command(
  args : Array[String],
  password : String?,
) -> Bool {
  guard args.get(1) is Some(command) &&
    ["source-diff", "source-sfx-diff"].contains(command) else {
    return false
  }
  guard args.length() == 5 && args[2] == "--json" else {
    fail("usage: source-diff|source-sfx-diff --json LEFT RIGHT")
  }
  if command == "source-sfx-diff" {
    let left = @host.open_seekable_sfx_file(args[3], password?)
    defer left.close()
    let right = @host.open_seekable_sfx_file(args[4], password?)
    defer right.close()
    println(
      left.embedded.archive
      .compare(right.embedded.archive)
      .to_json()
      .stringify(),
    )
  } else {
    let left = @host.open_seekable_file(args[3], password?)
    defer left.close()
    let right = @host.open_seekable_file(args[4], password?)
    defer right.close()
    println(left.archive.compare(right.archive).to_json().stringify())
  }
  true
}
