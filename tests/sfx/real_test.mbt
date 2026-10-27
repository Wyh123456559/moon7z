///|
test "official SDK GUI console and configured installer envelopes reproduce exact member bytes" {
  for (encoded, offset) in [(gui, 35328), (console, 34816), (installer, 129082)] {
    let input = @base64.decode(encoded.split("\n").join(""))
    let imported = @archive.EmbeddedArchive::open(input)
    assert_eq(imported.prefix[:2].to_owned(), b"MZ")
    assert_eq(imported.prefix.length(), offset)
    assert_eq(imported.payload.length(), 5550)
    assert_eq(imported.suffix, b"")
    assert_eq(imported.prefix + imported.payload + imported.suffix, input)
    assert_eq(imported.archive.verify().bytes, 14229)
    let expected : Map[String, Bytes] = {
      "README.md": readme,
      "LICENSE": license,
      "清单.json": manifest,
    }
    for item in imported.archive.extract_all() {
      assert_eq(item.bytes, expected[item.entry.name])
    }
    let reader = imported.archive.reader()
    for entry in imported.archive.entries() {
      assert_eq(
        reader.read_range(entry.id, offset=0, length=1),
        expected[entry.name][:1].to_owned(),
      )
    }
    let wrapped = input + b"\x00\xffopaque-footer"
    let trailing = @archive.EmbeddedArchive::open(wrapped)
    assert_eq(trailing.suffix, b"\x00\xffopaque-footer")
    assert_eq(trailing.prefix + trailing.payload + trailing.suffix, wrapped)
  }
}
