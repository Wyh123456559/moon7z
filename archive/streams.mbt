///|
fn read_streams(
  r : Cursor,
  limits : Limits,
  output_limit : Int32,
  buffers~ : Array[Bytes] = [],
) -> Streams raise ArchiveError {
  let mut id = r.byte()
  let mut pack_offset = 0
  let sizes : Array[Int32] = []
  let mut pack_crcs : Array[UInt32?] = []
  let blocks : Array[Block] = []
  let layouts : Array[Layout] = []
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
    let (folders, external) = r.external(buffers)
    for _ in 0..<n {
      let layout = read_pipeline(folders, limits~)
      layouts.push(layout)
      blocks.push({
        coders: layout.ordered_coders(),
        size: 0,
        crc: None,
        pieces: [],
      })
    }
    if external {
      folders.end()
    }
    r.expect(12)
    let mut total = 0
    for index, block in blocks {
      let layout = layouts[index]
      let mut remaining = limits.working_bytes
      for i, coder in layout.nodes {
        let size = r.count(remaining, "folder coder output bytes")
        layout.sizes[i] = size
        remaining -= size
        validate_dictionary(coder, limits)
      }
      block.size = layout.sizes[layout.final_output]
      ignore(
        bounded(
          block.size.to_uint64(),
          output_limit - total,
          "total unpacked bytes",
        ),
      )
      total += block.size
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
  let mut packed_count = 0
  for layout in layouts {
    layout.pack_start = packed_count
    packed_count += layout.packed.length()
  }
  guard sizes.length() == packed_count else {
    raise Invalid(
      offset=r.pos,
      reason="pack stream count differs from all folder input mappings",
    )
  }
  for layout in layouts {
    validate_graph_sizes(layout, sizes)
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
  { pack_offset, pack_sizes: sizes, pack_crcs, blocks, layouts, }
}
