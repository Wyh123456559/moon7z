///|
fn validate_coder(coder : Coder) -> Unit raise ArchiveError {
  if is_legacy_branch(coder.codec_id) {
    validate_branch(coder)
    return
  }
  match coder.codec_id {
    b"\x03\x03\x01\x1b" =>
      if !coder.properties.is_empty() {
        raise Invalid(offset=0, reason="BCJ2 has no coder properties")
      }
    b"\x02\x03\x02" | b"\x02\x03\x04" =>
      if !coder.properties.is_empty() {
        raise Invalid(offset=0, reason="Swap2/Swap4 have no coder properties")
      }
    b"\x0a" => {
      guard coder.properties.is_empty() || coder.properties.length() == 4 else {
        raise Invalid(
          offset=0,
          reason="ARM64 needs zero or four offset property bytes",
        )
      }
      if !coder.properties.is_empty() &&
        (Cursor::new(coder.properties).u32() & 3U) != 0U {
        raise Invalid(
          offset=0,
          reason="ARM64 start offset must be a multiple of four",
        )
      }
    }
    b"\x03\x03\x01\x03" =>
      if !coder.properties.is_empty() {
        raise Unsupported(
          feature="x86 BCJ properties; only the zero-offset 7z method is supported",
        )
      }
    b"\x03" =>
      if coder.properties.length() != 1 {
        raise Invalid(offset=0, reason="Delta needs one distance property byte")
      }
    b"\x00" =>
      if !coder.properties.is_empty() {
        raise Invalid(offset=0, reason="Copy coder has properties")
      }
    b"\x03\x01\x01" => {
      guard coder.properties.length() == 5 else {
        raise Invalid(offset=0, reason="LZMA needs five property bytes")
      }
      let p = coder.properties[0].to_int()
      guard p < 225 && p % 9 + p / 9 % 5 <= 4 else {
        raise Unsupported(
          feature="LZMA lc/lp properties outside decoder support",
        )
      }
    }
    b"\x21" => {
      guard coder.properties.length() == 1 && coder.properties[0].to_int() <= 40 else {
        raise Invalid(offset=0, reason="invalid LZMA2 dictionary property")
      }
    }
    _ => raise Unsupported(feature="compression method \{coder.codec_id}")
  }
}

///|
fn dictionary(coder : Coder) -> UInt64 raise ArchiveError {
  if is_filter(coder.codec_id) {
    return 0UL
  }
  match coder.codec_id {
    b"\x00" | b"\x03\x03\x01\x1b" => 0UL
    b"\x03\x01\x01" => {
      let r = Cursor::new(coder.properties[1:].to_owned())
      let size = r.u32().to_uint64()
      if size < 4096UL {
        4096UL
      } else {
        size
      }
    }
    b"\x21" => {
      let p = coder.properties[0].to_int()
      if p == 40 {
        0xffffffffUL
      } else {
        (2 + (p & 1)).to_uint64() << (p / 2 + 11)
      }
    }
    _ => raise Unsupported(feature="dictionary for unknown coder")
  }
}

///|
fn validate_dictionary(
  coder : Coder,
  limits : Limits,
) -> Unit raise ArchiveError {
  ignore(
    bounded(dictionary(coder), limits.dictionary_bytes, "dictionary bytes"),
  )
}

///|
/// Inspect LZMA2 chunk headers before handing control to the codec. Its
/// memlimit controls dictionary size, not expansion. No chunk may exceed the
/// declared folder output; the complete stream must end at exactly that size.
fn preflight_lzma2(packed : Bytes, expected : Int32) -> Unit raise ArchiveError {
  let r = Cursor::new(packed)
  let mut remaining = expected
  for ;; {
    let c = r.byte()
    if c == 0 {
      break
    }
    let (unpacked, compressed) = if c == 1 || c == 2 {
      let size = ((r.byte() << 8) | r.byte()) + 1
      (size, size)
    } else if c >= 0x80 {
      let unpacked = (((c & 31) << 16) | (r.byte() << 8) | r.byte()) + 1
      let compressed = ((r.byte() << 8) | r.byte()) + 1
      if c >= 0xc0 {
        ignore(r.byte())
      }
      (unpacked, compressed)
    } else {
      raise Invalid(offset=r.pos - 1, reason="invalid LZMA2 chunk control")
    }
    guard unpacked <= remaining else {
      raise Invalid(offset=r.pos, reason="LZMA2 chunk exceeds declared output")
    }
    remaining -= unpacked
    ignore(r.take(compressed))
  }
  r.end()
  guard remaining == 0 else {
    raise Invalid(
      offset=r.pos,
      reason="LZMA2 chunk sizes differ from declared output",
    )
  }
}

///|
fn decode(
  block : Block,
  packed : Bytes,
  limits : Limits,
) -> Bytes raise ArchiveError {
  let coder = block.coders[0]
  validate_dictionary(coder, limits)
  let mut output = match coder.codec_id {
    b"\x00" => packed
    b"\x03\x01\x01" => {
      let alone = @buffer.Buffer()
      alone.write_bytes(coder.properties)
      alone.write_uint64_le(block.size.to_uint64())
      alone.write_bytes(packed)
      @lzma.decode_alone(alone.to_bytes(), limits.dictionary_bytes.to_uint64()) catch {
        _ => raise Codec(reason="invalid or truncated compressed data")
      }
    }
    b"\x21" => {
      preflight_lzma2(packed, block.size)
      @lzma2.decode_lzma2(
        packed,
        limits.dictionary_bytes.to_uint64(),
        dict_size=dictionary(coder).to_uint(),
      ) catch {
        _ => raise Codec(reason="invalid or truncated LZMA2 data")
      }
    }
    _ => raise Unsupported(feature="initial compression coder")
  }
  guard output.length() == block.size else {
    raise Invalid(offset=0, reason="decoded folder length mismatch")
  }
  for filter in block.coders[1:] {
    output = match filter.codec_id {
      b"\x03\x03\x05\x01" => @filters.bcj_arm(output[:], 0U, false)
      b"\x03\x03\x07\x01" => @filters.bcj_armthumb(output[:], 0U, false)
      b"\x03\x03\x02\x05" => @filters.bcj_powerpc(output[:], 0U, false)
      b"\x03\x03\x04\x01" => @filters.bcj_ia64(output[:], 0U, false)
      b"\x03\x03\x08\x05" => @filters.bcj_sparc(output[:], 0U, false)
      b"\x02\x03\x02" => swap_bytes(output, 2)
      b"\x02\x03\x04" => swap_bytes(output, 4)
      b"\x03" =>
        @filters.delta_decode(output[:], filter.properties[0].to_int() + 1) catch {
          _ => raise Codec(reason="invalid Delta filter distance")
        }
      b"\x03\x03\x01\x03" => bcj_decode(output)
      b"\x0a" => {
        let start = if filter.properties.is_empty() {
          0U
        } else {
          Cursor::new(filter.properties).u32()
        }
        @filters.bcj_arm64(output[:], start, false)
      }
      _ => raise Unsupported(feature="filter in decode chain")
    }
  }
  check_crc(output, block.crc, "folder")
  output
}

///|
fn decode_streams(
  input : Bytes,
  streams : Streams,
  limits : Limits,
) -> Array[Bytes] raise ArchiveError {
  let output : Array[Bytes] = []
  let mut offset = 32 + streams.pack_offset
  for i in 0..<streams.blocks.length() {
    output.push(decode_packed_stream(input, streams, i, offset, limits))
    offset += packed_folder_bytes(streams, i)
  }
  output
}

///|
fn decode_packed_stream(
  input : Bytes,
  streams : Streams,
  id : Int32,
  start : Int32,
  limits : Limits,
) -> Bytes raise ArchiveError {
  let (first, count) = pack_range(streams, id)
  let packed : Array[Bytes] = []
  let mut offset = start
  for stream in first..<(first + count) {
    let length = streams.pack_sizes[stream]
    guard offset >= 0 &&
      offset <= input.length() &&
      length <= input.length() - offset else {
      raise Invalid(offset~, reason="packed stream outside archive")
    }
    let bytes = input[offset:offset + length].to_owned()
    check_crc(bytes, streams.pack_crcs[stream], "packed stream \{stream}")
    packed.push(bytes)
    offset += length
  }
  if streams.layouts.is_empty() {
    decode(streams.blocks[id], packed[0], limits)
  } else {
    let result = decode_graph(streams.layouts[id], packed, limits)
    check_crc(result, streams.blocks[id].crc, "folder")
    result
  }
}
