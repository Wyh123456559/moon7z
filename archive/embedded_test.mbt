///|
test "embedded round trip preserves arbitrary envelope and ordinary open stays strict" {
  let prefix = b"\x00\xffstub\x00"
  let suffix = b"\x80\x00signature-or-trailer"
  let bytes = prefix + producer_v2605_copy + suffix
  let imported = @archive.EmbeddedArchive::open(bytes)
  assert_eq(imported.prefix, prefix)
  assert_eq(imported.payload, producer_v2605_copy)
  assert_eq(imported.suffix, suffix)
  assert_eq(imported.prefix + imported.payload + imported.suffix, bytes)
  assert_eq(imported.archive.verify().bytes, 14550)
  assert_true(
    imported.archive
    .compare(@archive.Archive::open(producer_v2605_copy))
    .identical(),
  )
  assert_true(
    capture(() => @archive.Archive::open(bytes)) is Err(@archive.Invalid(..)),
  )
  assert_true(
    capture(() => @archive.Archive::open(producer_v2605_copy + suffix))
    is Err(@archive.Invalid(..)),
  )
  let json = imported.inventory_json()
  assert_eq(@json.parse(json.stringify()), json)
  assert_eq(imported.inventory_json().stringify(), json.stringify())
  assert_true(
    json
    is {
      "contents_verified": False,
      "envelope_verified": False,
      "prefix_base64": String("AP9zdHViAA=="),
      ..
    },
  )
}

///|
test "bounded discovery skips bad CRC but never hides a credible first archive failure" {
  let decoy = producer_v2605_copy[:32].to_owned().to_array()
  decoy[8] = decoy[8] ^ b'\x01'
  let prefix = Bytes::from_array(decoy) + b"gap"
  assert_true(
    capture(() => @archive.EmbeddedArchive::open_at(Bytes::from_array(decoy), 0))
    is Err(@archive.Checksum(..)),
  )
  let input = prefix + producer_v2605_copy
  assert_true(
    capture(() => {
      @archive.EmbeddedArchive::open(
        input,
        limits=@archive.Limits::new(header_bytes=0),
      )
    })
    is Err(@archive.Limit(..)),
  )
  assert_eq(@archive.EmbeddedArchive::open(input).prefix, prefix)
  assert_true(
    capture(() => {
      @archive.EmbeddedArchive::open(input, search_bytes=prefix.length())
    })
    is Err(@archive.SignatureNotFound(..)),
  )
  assert_eq(
    @archive.EmbeddedArchive::open(input, search_bytes=prefix.length() + 1).prefix,
    prefix,
  )
  let broken = producer_v2605_copy.to_array()
  broken[broken.length() - 1] = broken[broken.length() - 1] ^ b'\x01'
  let both = Bytes::from_array(broken) + producer_v2605_copy
  assert_true(
    capture(() => @archive.EmbeddedArchive::open(both))
    is Err(@archive.Checksum(..)),
  )
  assert_eq(
    @archive.EmbeddedArchive::open_at(both, broken.length()).archive.verify().bytes,
    14550,
  )
  let version = producer_v2605_copy.to_array()
  version[6] = b'\x01'
  assert_true(
    capture(() => {
      @archive.EmbeddedArchive::open(
        Bytes::from_array(version) + producer_v2605_copy,
      )
    })
    is Err(@archive.Unsupported(..)),
  )
  let two = producer_v2605_copy + producer_v2605_copy
  assert_eq(@archive.EmbeddedArchive::open(two).suffix, producer_v2605_copy)
}

///|
test "embedded boundaries limits password recovery and truncation are explicit" {
  let input = b"MZ" + ppmd_encrypted
  assert_true(
    capture(() => @archive.EmbeddedArchive::open(input))
    is Err(@archive.PasswordRequired),
  )
  assert_true(
    capture(() => @archive.EmbeddedArchive::open(input, password="wrong"))
    is Err(@archive.DecryptionFailed),
  )
  assert_eq(
    @archive.EmbeddedArchive::open(input, password="moon7z-ppmd").archive.verify().bytes,
    14229,
  )
  for offset in [-1, input.length() - 31, input.length(), 0x7fffffff] {
    assert_true(
      capture(() => @archive.EmbeddedArchive::open_at(input, offset))
      is Err(@archive.Invalid(..)),
    )
  }
  for size in [-1, 0x40000000] {
    assert_true(
      capture(() => @archive.EmbeddedArchive::open(input, search_bytes=size))
      is Err(@archive.Invalid(..)),
    )
  }
  assert_true(
    capture(() => @archive.EmbeddedArchive::open(input, search_bytes=0))
    is Err(@archive.SignatureNotFound(searched_bytes=0)),
  )
  assert_true(
    capture(() => {
      @archive.EmbeddedArchive::open(
        input,
        limits=@archive.Limits::new(input_bytes=input.length() - 1),
      )
    })
    is Err(@archive.Limit(..)),
  )
  assert_true(
    capture(() => {
      @archive.EmbeddedArchive::open(
        input,
        limits=@archive.Limits::new(header_bytes=-1),
      )
    })
    is Err(@archive.Invalid(..)),
  )
  assert_true(
    capture(() => {
      @archive.EmbeddedArchive::open(
        producer_v2605_copy[:producer_v2605_copy.length() - 1].to_owned(),
      )
    })
    is Err(@archive.Invalid(..)),
  )
  assert_true(
    capture(() => @archive.EmbeddedArchive::open(b"short"))
    is Err(@archive.Invalid(..)),
  )
  let far = b"\x00".repeat(1048576) + producer_v2605_copy
  assert_true(
    capture(() => @archive.EmbeddedArchive::open(far))
    is Err(@archive.SignatureNotFound(..)),
  )
  assert_eq(
    @archive.EmbeddedArchive::open(far, search_bytes=1048577).archive.verify().bytes,
    14550,
  )
}
