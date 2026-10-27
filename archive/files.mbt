///|
fn read_times(
  r : Cursor,
  count : Int32,
  buffers~ : Array[Bytes] = [],
) -> Array[UInt64?] raise ArchiveError {
  let defined = r.defined(count)
  let (data, _) = r.external(buffers)
  let values : Array[UInt64?] = []
  for present in defined {
    values.push(if present { Some(data.u64()) } else { None })
  }
  data.end()
  values
}

///|
fn read_names(
  source : Cursor,
  count : Int32,
  buffers~ : Array[Bytes] = [],
) -> Array[String] raise ArchiveError {
  let (r, _) = source.external(buffers)
  let names : Array[String] = []
  let mut start = r.pos
  while r.pos < r.data.length() {
    let lo = r.byte()
    let hi = r.byte()
    if lo == 0 && hi == 0 {
      guard names.length() < count else {
        raise Invalid(
          offset=r.pos - 2,
          reason="more filenames than declared entries",
        )
      }
      let name = @utf16.decode(
        r.data[start:r.pos - 2],
        ignore_bom=true,
        endianness=Little,
      ) catch {
        _ => raise Invalid(offset=start, reason="malformed UTF-16 filename")
      }
      names.push(name)
      start = r.pos
    }
  }
  guard start == r.pos && names.length() == count else {
    raise Invalid(offset=r.pos, reason="filename count or terminator mismatch")
  }
  names
}

///|
fn read_files(
  r : Cursor,
  streams : Streams,
  limits : Limits,
  buffers~ : Array[Bytes] = [],
  properties~ : Array[FileProperty] = [],
) -> Array[Entry] raise ArchiveError {
  let count = r.count(limits.entries, "file entries")
  let mut names : Array[String]? = None
  let mut empty = Array::make(count, false)
  let mut empty_file : Array[Bool] = []
  let mut anti_file : Array[Bool] = []
  let mut positions : Array[UInt64?] = Array::make(count, None)
  let mut created : Array[UInt64?] = Array::make(count, None)
  let mut accessed : Array[UInt64?] = Array::make(count, None)
  let mut modified : Array[UInt64?] = Array::make(count, None)
  let mut attributes : Array[UInt32?] = Array::make(count, None)
  let seen : Set[UInt64] = Set([])
  let mut records = 0
  for ;; {
    let property = r.number()
    if property == 0UL {
      break
    }
    records += 1
    ignore(
      bounded(
        records.to_uint64(),
        limits.file_property_records,
        "file property records",
      ),
    )
    let recognized = (property >= 14UL && property <= 21UL) || property == 24UL
    guard !recognized || !seen.contains(property) else {
      raise Invalid(
        offset=r.pos - 1,
        reason="duplicate file property \{property}",
      )
    }
    seen.add(property)
    let p = Cursor::new(
      r.take(r.count(limits.header_bytes, "file property bytes")),
    )
    match property {
      14UL => empty = p.bits(count)
      15UL => {
        guard seen.contains(14UL) else {
          raise Invalid(offset=r.pos, reason="EmptyFile precedes EmptyStream")
        }
        empty_file = p.bits(empty.filter(x => x).length())
      }
      16UL => {
        guard seen.contains(14UL) else {
          raise Invalid(offset=r.pos, reason="Anti precedes EmptyStream")
        }
        anti_file = p.bits(empty.filter(x => x).length())
      }
      17UL => names = Some(read_names(p, count, buffers~))
      18UL => created = read_times(p, count, buffers~)
      19UL => accessed = read_times(p, count, buffers~)
      20UL => modified = read_times(p, count, buffers~)
      24UL => positions = read_times(p, count, buffers~)
      21UL => {
        let defined = p.defined(count)
        let (data, _) = p.external(buffers)
        attributes = []
        for present in defined {
          attributes.push(if present { Some(data.u32()) } else { None })
        }
        data.end()
      }
      25UL =>
        for byte in p.take(p.data.length()) {
          if byte != b'\x00' {
            raise Invalid(offset=p.pos, reason="nonzero padding")
          }
        }
      _ => properties.push({ id: property, data: p.take(p.data.length()), })
    }
    p.end()
  }
  let names = match names {
    Some(names) => names
    None =>
      if count == 0 {
        []
      } else {
        raise Invalid(offset=r.pos, reason="missing filenames")
      }
  }
  let pieces : Array[(Int32, Int32, UInt32?)] = []
  for block_id, block in streams.blocks {
    for (size, crc) in block.pieces {
      pieces.push((block_id, size, crc))
    }
  }
  let entries : Array[Entry] = []
  let mut stream_index = 0
  let mut empty_index = 0
  for id in 0..<count {
    let anti = empty[id] && anti_file.get(empty_index).unwrap_or(false)
    let (kind, size, crc, block) = if empty[id] {
      let file = empty_file.get(empty_index).unwrap_or(false)
      empty_index += 1
      (if file { File } else { Directory }, 0, None, None)
    } else {
      guard pieces.get(stream_index) is Some((block, size, crc)) else {
        raise Invalid(offset=r.pos, reason="file has no data substream")
      }
      stream_index += 1
      (File, size, crc, Some(block))
    }
    if attributes[id] is Some(attr) {
      let mode = if (attr & 0x8000U) != 0U {
        (attr >> 16) & 0xf000U
      } else {
        0U
      }
      if classify_attributes(Some(attr)) == Regular &&
        (
          ((attr & 0x10U) != 0U) != (kind == Directory) ||
          (mode == 0x4000U && kind != Directory) ||
          (mode == 0x8000U && kind != File)
        ) {
        raise Invalid(
          offset=r.pos,
          reason="file kind disagrees with attributes",
        )
      }
    }
    entries.push({
      anti,
      id,
      name: names[id],
      kind,
      size,
      crc32: crc,
      block,
      metadata: {
        start_position: positions[id],
        created: created[id],
        accessed: accessed[id],
        modified: modified[id],
        attributes: attributes[id],
      },
    })
  }
  guard stream_index == pieces.length() else {
    raise Invalid(offset=r.pos, reason="unused data substreams")
  }
  entries
}
