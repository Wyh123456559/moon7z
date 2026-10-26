///|
test "7z key derivation includes salt UTF16 password and little endian counters with cumulative budgets" {
  let secret = @utf16.encode("密码🔑"[:], bom=false, endianness=Little)
  let limits = Limits::new(
    kdf_rounds=2,
    kdf_bytes=(1 + secret.length() + 8) * 2,
  )
  let state = CryptState::new(Some(secret), limits)
  let salt = b"\x42"
  let expected = @crypto.sha256(
    salt +
    secret +
    b"\x00".repeat(8) +
    salt +
    secret +
    b"\x01" +
    b"\x00".repeat(7),
  )
  let key = state.key(1, salt)
  assert_eq(key, Bytes::makei(32, i => expected[i]))
  assert_eq(state.rounds_left, 0)
  assert_eq(state.bytes_left, 0)
  assert_eq(state.key(1, salt), key)
  let capped = try {
    ignore(state.key(0, b"different"))
    false
  } catch {
    Limit(..) => true
    _ => false
  }
  assert_true(capped)
  assert_eq(state.key(1, salt), key)
  let direct = CryptState::new(
    Some(b""),
    Limits::new(kdf_rounds=0, kdf_bytes=0),
  )
  assert_eq(direct.key(63, b"salt"), b"salt" + b"\x00".repeat(28))
  let missing = try {
    ignore(CryptState::new(None, limits).key(63, b""))
    false
  } catch {
    PasswordRequired => true
    _ => false
  }
  assert_true(missing)
  let work = try {
    ignore(CryptState::new(Some(secret), Limits::new(kdf_bytes=1)).key(0, b""))
    false
  } catch {
    Limit(..) => true
    _ => false
  }
  assert_true(work)
  let exponent = try {
    ignore(state.key(62, b""))
    false
  } catch {
    Limit(..) => true
    _ => false
  }
  assert_true(exponent)
}

///|
test "AES properties exact padding roundtrip empty password and malformed inputs" {
  let state = CryptState::new(Some(b""), Limits::new())
  let key = state.key(63, b"")
  let zero = b"\x00".repeat(16)
  let (default_cycles, default_salt, default_iv) = aes_properties(b"")
  assert_eq(default_cycles, 0)
  assert_eq(default_salt, b"")
  assert_eq(default_iv, zero)
  let original = b"hello"
  let ciphertext = @crypto.aes_cbc_encrypt(
    key[:],
    zero[:],
    (original + b"\x00".repeat(11))[:],
  )
  assert_eq(decode_aes(ciphertext, 5, b"\x3f", state), original)
  let refused = try {
    ignore(decode_aes(ciphertext, 4, b"\x3f", state))
    false
  } catch {
    DecryptionFailed => true
    _ => false
  }
  assert_true(refused)
  let sizes = try {
    ignore(decode_aes(ciphertext, 0, b"\x3f", state))
    false
  } catch {
    Invalid(..) => true
    _ => false
  }
  assert_true(sizes)
  let properties = b"\xff\xff" + b"s".repeat(16) + b"i".repeat(16)
  let (cycles, salt, iv) = aes_properties(properties)
  assert_eq(cycles, 63)
  assert_eq(salt, b"s".repeat(16))
  assert_eq(iv, b"i".repeat(16))
  let salted_key = state.key(63, salt)
  let salted_cipher = @crypto.aes_cbc_encrypt(
    salted_key[:],
    iv[:],
    (original + b"\x00".repeat(11))[:],
  )
  assert_eq(decode_aes(salted_cipher, 5, properties, state), original)
  for length in 1..<properties.length() {
    let refused = try {
      ignore(aes_properties(properties[:length].to_owned()))
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(refused)
  }
  for bad in [b"\x3f\x00", properties + b"\x00"] {
    let refused = try {
      ignore(aes_properties(bad))
      false
    } catch {
      Invalid(..) => true
      _ => false
    }
    assert_true(refused)
  }
  assert_eq(decode_aes(ciphertext, 5, b"\x3f", state), original)
}
