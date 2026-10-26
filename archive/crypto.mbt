///|
/// Secret material has no public getter, Debug or JSON implementation.
priv struct CryptState {
  password : Bytes?
  keys : Array[(Bytes, Bytes)]
  mut rounds_left : Int32
  mut bytes_left : Int32
  maximum_rounds : Int32
  maximum_bytes : Int32
  mut encrypted : Bool
}

///|
fn CryptState::new(password : Bytes?, limits : Limits) -> CryptState {
  {
    password,
    keys: [],
    rounds_left: limits.kdf_rounds,
    bytes_left: limits.kdf_bytes,
    maximum_rounds: limits.kdf_rounds,
    maximum_bytes: limits.kdf_bytes,
    encrypted: false,
  }
}

///|
fn aes_properties(
  properties : Bytes,
) -> (Int32, Bytes, Bytes) raise ArchiveError {
  if properties.is_empty() {
    return (0, b"", b"\x00".repeat(16))
  }
  let input = Cursor::new(properties)
  let flags = input.byte()
  let cycles = flags & 63
  let (salt_size, iv_size) = if (flags & 192) == 0 {
    (0, 0)
  } else {
    let sizes = input.byte()
    (((flags >> 7) & 1) + (sizes >> 4), ((flags >> 6) & 1) + (sizes & 15))
  }
  let salt = input.take(salt_size)
  let iv = input.take(iv_size) + b"\x00".repeat(16 - iv_size)
  input.end()
  (cycles, salt, iv)
}

///|
fn CryptState::key(
  self : CryptState,
  cycles : Int32,
  salt : Bytes,
) -> Bytes raise ArchiveError {
  let password = match self.password {
    Some(value) => value
    None => raise PasswordRequired
  }
  let identity = Bytes::from_array([cycles.to_byte()]) + salt
  for (id, key) in self.keys {
    if identity == id {
      return key
    }
  }
  let key = if cycles == 63 {
    let source = salt + password
    Bytes::makei(32, i => if i < source.length() { source[i] } else { b'\x00' })
  } else {
    guard cycles < 30 else {
      raise Limit(
        resource="password derivation rounds",
        maximum=self.maximum_rounds,
      )
    }
    let rounds = 1 << cycles
    guard rounds <= self.rounds_left else {
      raise Limit(
        resource="password derivation rounds",
        maximum=self.maximum_rounds,
      )
    }
    let prefix = salt + password
    let work = (prefix.length().to_uint64() + 8UL) * rounds.to_uint64()
    guard work <= self.bytes_left.to_uint64() else {
      raise Limit(
        resource="password derivation bytes",
        maximum=self.maximum_bytes,
      )
    }
    self.rounds_left -= rounds
    self.bytes_left -= work.to_int()
    let hash = @crypto.SHA256::new()
    let counter = FixedArray::make(8, b'\x00')
    for _ in 0..<rounds {
      hash.update(prefix)
      hash.update(counter)
      for i in 0..<8 {
        counter[i] = (counter[i].to_int() + 1).to_byte()
        if counter[i] != b'\x00' {
          break
        }
      }
    }
    let digest = FixedArray::make(32, b'\x00')
    @crypto.CryptoHasher::finalize_into(hash, digest, offset=0)
    Bytes::makei(32, i => digest[i])
  }
  if self.keys.length() == 64 {
    ignore(self.keys.remove(0))
  }
  self.keys.push((identity, key))
  key
}

///|
fn decode_aes(
  packed : Bytes,
  size : Int32,
  properties : Bytes,
  state : CryptState,
) -> Bytes raise ArchiveError {
  state.encrypted = true
  let (cycles, salt, iv) = aes_properties(properties)
  guard packed.length() % 16 == 0 &&
    size <= packed.length() &&
    packed.length() - size < 16 else {
    raise Invalid(
      offset=0,
      reason="AES ciphertext does not match declared padded size",
    )
  }
  let key = state.key(cycles, salt)
  let plain = @crypto.aes_cbc_decrypt(key[:], iv[:], packed[:]) catch {
    _ => raise DecryptionFailed
  }
  for byte in plain[size:] {
    guard byte == b'\x00' else { raise DecryptionFailed }
  }
  plain[:size].to_owned()
}

///|
/// True when the inventory's data or decoded header uses the 7z AES method.
/// This describes encryption presence, not authenticity or password validity.
pub fn Archive::is_encrypted(self : Archive) -> Bool {
  self.crypto.encrypted
}

///|
fn encrypted_error(block : Block, error : ArchiveError) -> ArchiveError {
  if block.coders.any(coder => coder.codec_id == b"\x06\xf1\x07\x01") {
    match error {
      Invalid(..) | Codec(..) | Checksum(..) => DecryptionFailed
      _ => error
    }
  } else {
    error
  }
}
