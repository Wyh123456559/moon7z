///|
fn is_legacy_branch(codec : Bytes) -> Bool {
  match codec {
    b"\x03\x03\x02\x05"
    | b"\x03\x03\x05\x01"
    | b"\x03\x03\x08\x05"
    | b"\x03\x03\x07\x01"
    | b"\x03\x03\x04\x01" => true
    _ => false
  }
}

///|
fn validate_branch(coder : Coder) -> Unit raise ArchiveError {
  if !coder.properties.is_empty() {
    raise Unsupported(
      feature="classic 7z branch filter properties; only the zero-offset method is supported",
    )
  }
}

///|
fn is_filter(codec : Bytes) -> Bool {
  is_legacy_branch(codec) ||
  codec == b"\x03" ||
  codec == b"\x03\x03\x01\x03" ||
  codec == b"\x0a" ||
  codec == b"\x02\x03\x02" ||
  codec == b"\x02\x03\x04"
}

///|
/// Full groups reverse byte order; an incomplete final group passes unchanged.
fn swap_bytes(input : Bytes, width : Int32) -> Bytes {
  let complete = input.length() / width * width
  Bytes::makei(input.length(), i => {
    if i < complete {
      input[i / width * width + width - 1 - i % width]
    } else {
      input[i]
    }
  })
}
