///|
suberror AuditReadFailure derive(Debug)

///|
async test "positioned audit isolates corrupt folders retains metadata and recovers" {
  let original = @fs.read_file("corpus/copy-plain.7z").binary()
  let changed = original.to_array()
  changed[32] = (changed[32].to_int() ^ 1).to_byte()
  let damaged = Bytes::from_array(changed)
  let input = @archive.SeekableInput::new(damaged.length().to_uint64(), (
    offset,
    length,
  ) => damaged[offset.to_int():offset.to_int() + length].to_owned())
  let source = @archive.SourceArchive::open(input)
  let report = source.audit()
  let memory = @archive.Archive::open(damaged).audit()
  assert_eq(
    report.folders().map(folder => folder.passed()),
    memory.folders().map(folder => folder.passed()),
  )
  assert_eq(report.files_without_crc(), memory.files_without_crc())
  assert_eq(report.entries_without_data(), memory.entries_without_data())
  assert_true(!report.all_available_checks_passed())
  assert_true(report.folders()[0].error is Some(@archive.Checksum(..)))
  assert_true(report.folders()[1].passed())
  assert_true(
    source.reader().read(report.folders()[1].entries()[0].id).bytes.length() > 0,
  )
  assert_true(
    try {
      ignore(source.verify())
      false
    } catch {
      @archive.Checksum(..) => true
      _ => false
    },
  )
  assert_eq(report.to_json().stringify(), source.audit().to_json().stringify())
  let envelope = memory_input(b"stub" + damaged + b"footer")
  let embedded = @archive.SourceEmbeddedArchive::open(
    @archive.SeekableInput::concat([
      envelope.slice(0UL, 19UL),
      envelope.slice(19UL, envelope.size - 19UL),
    ]),
  )
  assert_eq(embedded.archive.audit().to_json(), report.to_json())
  assert_eq(@json.parse(report.to_json().stringify()), report.to_json())
  let results = report.folders()
  results.clear()
  assert_eq(report.folders().length(), 4)
  let healthy = @archive.SourceArchive::open(
    @archive.SeekableInput::new(original.length().to_uint64(), (offset, length) => {
      original[offset.to_int():offset.to_int() + length].to_owned()
    }),
  )
  assert_true(healthy.audit().all_available_checks_passed())
}

///|
async test "audit propagates source failures unchanged and permits retry" {
  let bytes = @fs.read_file("corpus/copy-plain.7z").binary()
  let mut broken = false
  let source = @archive.SeekableInput::new(bytes.length().to_uint64(), (
    offset,
    length,
  ) => {
    if broken && offset == 32UL {
      raise AuditReadFailure
    }
    bytes[offset.to_int():offset.to_int() + length].to_owned()
  })
  let archive = @archive.SourceArchive::open(source)
  broken = true
  assert_true(
    try {
      ignore(archive.audit())
      false
    } catch {
      AuditReadFailure => true
      _ => false
    },
  )
  broken = false
  assert_true(archive.audit().all_available_checks_passed())
}

///|
async test "numeric volumes and official SDK SFX share positioned audit semantics" {
  let parts = Array::makei(6, i => {
    "corpus/volumes/variable/package.7z.00" + (i + 1).to_string()
  })
  let opened = @host.open_seekable_volumes(parts[:])
  defer opened.close()
  assert_true(opened.archive.audit().all_available_checks_passed())
  for name in ["gui", "console", "installer"] {
    let text = @fs.read_file("corpus/sfx/" + name + ".base64").text()
    let bytes = @base64.decode(text.split("\n").join(""))
    let embedded = @archive.SourceEmbeddedArchive::open(memory_input(bytes))
    assert_true(embedded.archive.audit().all_available_checks_passed())
  }
}
