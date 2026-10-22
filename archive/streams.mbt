///|
fn read_coder(r : Cursor) -> Coder raise ArchiveError {
  let count = r.number()
  guard count == 1UL else {
    raise Unsupported(feature="coder graphs with multiple coders")
  }
  let flags = r.byte()
  let id_size = flags & 15
  guard id_size > 0 && id_size <= 8 && (flags & 0xc0) == 0 else {
    raise Invalid(
      offset=r.pos - 1,
      reason="invalid coder flags or method ID length",
    )
  }
  let codec_id = r.take(id_size)
  if (flags & 0x10) != 0 && (r.number() != 1UL || r.number() != 1UL) {
    raise Unsupported(feature="multiple-input or multiple-output coder")
  }
  let properties = if (flags & 0x20) != 0 {
    r.take(r.count(64, "coder properties"))
  } else {
    b""
  }
  let coder = { codec_id, properties, }
  validate_coder(coder)
  coder
}

///|
fn read_streams(
  r : Cursor,
  limits : Limits,
  output_limit : Int32,
) -> Streams raise ArchiveError {
  let mut id = r.byte()
  let mut pack_offset = 0
  let sizes : Array[Int32] = []
  let mut pack_crcs : Array[UInt32?] = []
  let blocks : Array[Block] = []
  if id == 6 {
    pack_offset = r.count(limits.input_bytes, "pack offset")
    let n = r.count(limits.entries, "pack streams")
    r.expect(9)
    for _ in 0..<n {
      sizes.push(r.count(limits.input_bytes, "packed stream bytes"))
    }
    id = r.byte()
    pack_crcs = if id == 10 {
      let crcs = r.crcs(n)
      id = r.byte()
      crcs
    } else {
      Array::make(n, None)
    }
    guard id == 0 else {
      raise Invalid(offset=r.pos - 1, reason="unexpected PackInfo property")
    }
    id = r.byte()
  }
  if id == 7 {
    r.expect(11)
    let n = r.count(limits.entries, "folders")
    if r.byte() != 0 {
      raise Unsupported(feature="external folder metadata")
    }
    for _ in 0..<n {
      blocks.push({ coder: read_coder(r), size: 0, crc: None, pieces: [], })
    }
    r.expect(12)
    let mut total = 0
    for block in blocks {
      block.size = r.count(output_limit - total, "total unpacked bytes")
      total += block.size
      validate_dictionary(block.coder, limits)
    }
    id = r.byte()
    if id == 10 {
      let crcs = r.crcs(n)
      for i in 0..<n {
        blocks[i].crc = crcs[i]
      }
      id = r.byte()
    }
    guard id == 0 else {
      raise Invalid(offset=r.pos - 1, reason="unexpected UnpackInfo property")
    }
    id = r.byte()
  }
  guard sizes.length() == blocks.length() else {
    raise Invalid(
      offset=r.pos,
      reason="one pack stream is required per supported folder",
    )
  }
  if id == 8 {
    let counts = Array::make(blocks.length(), 1)
    id = r.byte()
    if id == 13 {
      let mut total = 0
      for i in 0..<counts.length() {
        counts[i] = r.count(limits.entries - total, "substreams")
        total += counts[i]
      }
      id = r.byte()
    }
    if id != 9 && counts.any(n => n > 1) {
      raise Invalid(
        offset=r.pos,
        reason="solid folders require substream sizes",
      )
    }
    for i, block in blocks {
      let n = counts[i]
      let mut remaining = block.size
      for j in 0..<n {
        let size = if j == n - 1 {
          remaining
        } else {
          r.count(remaining, "substream bytes")
        }
        remaining -= size
        block.pieces.push((size, None))
      }
      if n == 0 && remaining != 0 {
        raise Invalid(offset=r.pos, reason="nonempty folder has no substreams")
      }
    }
    if id == 9 {
      id = r.byte()
    }
    let mut digest_count = 0
    for block in blocks {
      if !(block.pieces.length() == 1 && block.crc is Some(_)) {
        digest_count += block.pieces.length()
      }
    }
    let crcs = if id == 10 {
      let values = r.crcs(digest_count)
      id = r.byte()
      values
    } else {
      Array::make(digest_count, None)
    }
    let mut index = 0
    for block in blocks {
      if block.pieces.length() == 1 && block.crc is Some(crc) {
        block.pieces[0] = (block.size, Some(crc))
      } else {
        for j in 0..<block.pieces.length() {
          let (size, _) = block.pieces[j]
          block.pieces[j] = (size, crcs[index])
          index += 1
        }
      }
    }
    guard id == 0 else {
      raise Invalid(
        offset=r.pos - 1,
        reason="unexpected SubStreamsInfo property",
      )
    }
    id = r.byte()
  } else {
    for block in blocks {
      block.pieces.push((block.size, block.crc))
    }
  }
  guard id == 0 else { raise Unsupported(feature="streams property \{id}") }
  { pack_offset, pack_sizes: sizes, pack_crcs, blocks, }
}
