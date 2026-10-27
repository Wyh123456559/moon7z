///|
test "volume names reject gaps duplicates reordering mixed sets and invalid numeric roots" {
  for
    names in [
      [],
      ["a.7z"],
      [".001"],
      ["a.7z.002"],
      ["a.7z.aa"],
      ["a.7z.1"],
      ["a.7z.001", "a.7z.003"],
      ["a.7z.001", "a.7z.001"],
      ["a.7z.001", "b.7z.002"],
      ["a.7z.001", "a.7z.02"],
      ["a.7z.001", "a.7z.003", "a.7z.002"],
      ["../a.7z.001"],
      ["a\\b.001"],
      ["a\u0000.001"],
      ["a.9999999999"],
    ] {
    assert_true(
      capture(() => @archive.VolumeSequence::new(names[:]))
      is Err(@archive.VolumeError(..)),
    )
  }
  for limit in [0, -1, 0x40000000] {
    assert_true(
      capture(() => @archive.VolumeSequence::new(["a.001"], max_volumes=limit))
      is Err(@archive.VolumeError(..)),
    )
  }
  assert_true(
    capture(() => {
      @archive.VolumeSequence::new(["a.001", "a.002"], max_volumes=1)
    })
    is Err(@archive.Limit(..)),
  )
  let names = ["清单.7z.001", "清单.7z.002"]
  for
    other in [
      ["a.00", "a.01"],
      ["a.0000", "a.0001"],
      ["a.0000000001", "a.0000000002"],
    ] {
    assert_eq(@archive.VolumeSequence::new(other[:]).names(), other)
  }
  let sequence = @archive.VolumeSequence::new(names[:])
  names[0] = "changed"
  let copy = sequence.names()
  copy.clear()
  assert_eq(sequence.names(), ["清单.7z.001", "清单.7z.002"])
  let hundred = Array::makei(101, i => {
    "a." + (if i < 10 { "0" } else { "" }) + i.to_string()
  })
  assert_eq(
    @archive.VolumeSequence::new(hundred[:]).names().last(),
    Some("a.100"),
  )
  let thousand = Array::makei(1001, i => {
    "a." +
    "0".repeat((3 - (i + 1).to_string().length()).max(0)) +
    (i + 1).to_string()
  })
  assert_eq(
    @archive.VolumeSequence::new(thousand[:]).names().last(),
    Some("a.1001"),
  )
}

///|
test "every start-header split and variable part sizes preserve bytes and existing workflows" {
  for boundary in 1..<=33 {
    let sequence = @archive.VolumeSequence::new([
      "a.7z.001", "a.7z.002", "a.7z.003",
    ])
    let parts = [
      producer_v2605_copy[:boundary].to_owned(),
      producer_v2605_copy[boundary:boundary + 7].to_owned(),
      producer_v2605_copy[boundary + 7:].to_owned(),
    ]
    let split = sequence.open(parts[:])
    assert_eq(split.archive.verify().bytes, 14550)
    assert_true(
      split.archive
      .compare(@archive.Archive::open(producer_v2605_copy))
      .identical(),
    )
    assert_eq(split.volumes().map(part => part.offset), [
      0UL,
      boundary.to_uint64(),
      (boundary + 7).to_uint64(),
    ])
    assert_eq(
      split.volumes().map(part => part.bytes),
      parts.map(bytes => bytes.length()),
    )
    let info = split.volumes()
    info.clear()
    assert_eq(split.volumes().length(), 3)
    let json = split.inventory_json()
    assert_eq(@json.parse(json.stringify()), json)
    assert_eq(split.inventory_json().stringify(), json.stringify())
    assert_true(
      json
      is {
        "schema": String("moon7z.split_inventory.v1"),
        "contents_verified": False,
        "volumes": Array([{ "offset": String("0"), .. }, ..]),
        ..
      },
    )
  }
}

///|
test "volume budgets missing tails extra data and password failures leave fresh opens usable" {
  let sequence = @archive.VolumeSequence::new(["a.001", "a.002"])
  let parts = [
    producer_v2605_copy[:31].to_owned(),
    producer_v2605_copy[31:].to_owned(),
  ]
  assert_true(
    capture(() => {
      sequence.open(
        parts[:],
        limits=@archive.Limits::new(
          input_bytes=producer_v2605_copy.length() - 1,
        ),
      )
    })
    is Err(@archive.Limit(..)),
  )
  assert_eq(
    sequence.open(
      parts[:],
      limits=@archive.Limits::new(input_bytes=producer_v2605_copy.length()),
    ).archive.verify().bytes,
    14550,
  )
  assert_true(
    capture(() => sequence.open([b"", producer_v2605_copy]))
    is Err(@archive.VolumeError(..)),
  )
  assert_true(
    capture(() => sequence.open([producer_v2605_copy]))
    is Err(@archive.VolumeError(..)),
  )
  assert_true(
    capture(() => sequence.open([b"a", b"b"])) is Err(@archive.VolumeError(..)),
  )
  assert_true(
    capture(() => {
      sequence.open([
        producer_v2605_copy[:32].to_owned(),
        producer_v2605_copy[32:producer_v2605_copy.length() - 1].to_owned(),
      ])
    })
    is Err(@archive.VolumeError(..)),
  )
  assert_true(
    capture(() => sequence.open([producer_v2605_copy, b"extra"]))
    is Err(@archive.Invalid(..)),
  )
  let encrypted = [
    ppmd_encrypted[:19].to_owned(),
    ppmd_encrypted[19:].to_owned(),
  ]
  assert_true(
    capture(() => sequence.open(encrypted[:])) is Err(@archive.PasswordRequired),
  )
  assert_true(
    capture(() => sequence.open(encrypted[:], password="wrong"))
    is Err(@archive.DecryptionFailed),
  )
  assert_eq(
    sequence.open(encrypted[:], password="moon7z-ppmd").archive.verify().bytes,
    14229,
  )
  assert_eq(sequence.open(parts[:]).archive.verify().bytes, 14550)
}
