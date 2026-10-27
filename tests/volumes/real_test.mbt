///|
test "independent fixed variable and encrypted split sets preserve exact package members" {
  for
    (parts, encrypted) in [
      ([fixed1, fixed2, fixed3], false),
      (
        [variable1, variable2, variable3, variable4, variable5, variable6],
        false,
      ),
      ([encrypted1, encrypted2, encrypted3], true),
    ] {
    let names = Array::makei(parts.length(), i => {
      "package.7z.00" + (i + 1).to_string()
    })
    let sequence = @archive.VolumeSequence::new(names[:])
    let split = sequence.open(parts[:], password="moon7z-volumes")
    assert_eq(split.archive.is_encrypted(), encrypted)
    assert_eq(split.archive.verify().bytes, 14229)
    let expected : Map[String, Bytes] = {
      "README.md": readme,
      "LICENSE": license,
      "清单.json": manifest,
    }
    for item in split.archive.extract_all() {
      assert_eq(item.bytes, expected[item.entry.name])
    }
    let reader = split.archive.reader()
    for entry in split.archive.entries() {
      assert_eq(
        reader.read_range(entry.id, offset=0, length=1),
        expected[entry.name][:1].to_owned(),
      )
    }
    assert_true(split.archive.audit().all_available_checks_passed())
    let original = parts.fold(init=b"", (acc, part) => acc + part)
    assert_true(
      split.archive
      .compare(@archive.Archive::open(original, password="moon7z-volumes"))
      .identical(),
    )
    let json = split.inventory_json()
    assert_eq(@json.parse(json.stringify()), json)
    assert_eq(split.inventory_json().stringify(), json.stringify())
  }
}
