///|
test "Unicode passwords open encrypted headers and preserve verified member workflows" {
  for
    bytes in [
      encrypted_data, encrypted_header, encrypted_copy, encrypted_separate,
    ] {
    let archive = @archive.Archive::open(bytes, password="moon7z-密码-🔑")
    assert_true(archive.is_encrypted())
    let reader = archive.reader()
    for entry in archive.entries() {
      assert_eq(
        reader.read(entry.id).bytes,
        if entry.name == "part-a.bin" {
          x86_first
        } else {
          x86_second
        },
      )
    }
    assert_eq(archive.verify().bytes, 4099)
    assert_true(archive.audit().all_available_checks_passed())
    assert_true(
      archive
      .compare(
        @archive.Archive::open(encrypted_copy, password="moon7z-密码-🔑"),
      )
      .identical(),
    )
    assert_true(!archive.inventory_json().stringify().contains("moon7z-密码"))
  }
  assert_true(!@archive.Archive::open(copy_archive).is_encrypted())
  assert_eq(
    @archive.Archive::open(
      encrypted_header,
      password="moon7z-密码-🔑",
      limits=@archive.Limits::new(kdf_rounds=524288),
    ).verify().bytes,
    4099,
  )
}

///|
test "missing wrong and oversized passwords release no member and fresh-password retry works" {
  assert_true(
    capture(() => @archive.Archive::open(encrypted_header))
    is Err(@archive.PasswordRequired),
  )
  assert_true(
    capture(() => @archive.Archive::open(encrypted_header, password="wrong"))
    is Err(@archive.DecryptionFailed),
  )
  let missing = @archive.Archive::open(encrypted_data)
  assert_true(missing.is_encrypted())
  assert_eq(missing.entries().length(), 2)
  assert_true(
    capture(() => missing.reader().read(0)) is Err(@archive.PasswordRequired),
  )
  let wrong = @archive.Archive::open(encrypted_data, password="wrong").reader()
  for _ in 0..<2 {
    assert_true(capture(() => wrong.read(0)) is Err(@archive.DecryptionFailed))
    assert_eq(wrong.stats().cached_bytes, 0)
  }
  assert_true(
    capture(() => {
      @archive.Archive::open(
        encrypted_data,
        password="xx",
        limits=@archive.Limits::new(password_bytes=3),
      )
    })
    is Err(@archive.Limit(..)),
  )
  assert_true(
    capture(() => {
      @archive.Archive::open(
        encrypted_header,
        password="moon7z-密码-🔑",
        limits=@archive.Limits::new(kdf_rounds=0),
      )
    })
    is Err(@archive.Limit(..)),
  )
  assert_eq(
    @archive.Archive::open(encrypted_header, password="moon7z-密码-🔑").verify().bytes,
    4099,
  )
}
