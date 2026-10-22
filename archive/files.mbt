///|
fn read_times(r : Cursor, count : Int32) -> Array[UInt64?] raise ArchiveError {
  let defined = r.defined(count)
  if r.byte() != 0 {
    raise Unsupported(feature="external timestamps")
  }
  let values : Array[UInt64?] = []
  for present in defined {
    values.push(if present { Some(r.u64()) } else { None })
  }
  values
}

///|
fn read_names(r : Cursor, count : Int32) -> Array[String] raise ArchiveError {
  if r.byte() != 0 {
    raise Unsupported(feature="external filenames")
  }
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
) -> Array[Entry] raise ArchiveError {
  let count = r.count(limits.entries, "file entries")
  let mut names : Array[String]? = None
  let mut empty = Array::make(count, false)
  let mut empty_file : Array[Bool] = []
  let mut created : Array[UInt64?] = Array::make(count, None)
  let mut accessed : Array[UInt64?] = Array::make(count, None)
  let mut modified : Array[UInt64?] = Array::make(count, None)
  let mut attributes : Array[UInt32?] = Array::make(count, None)
  let seen : Set[Int32] = Set([])
  for ;; {
    let property = r.byte()
    if property == 0 {
      break
    }
    guard property == 25 || !seen.contains(property) else {
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
      14 => empty = p.bits(count)
      15 => {
        guard seen.contains(14) else {
          raise Invalid(offset=r.pos, reason="EmptyFile precedes EmptyStream")
        }
        empty_file = p.bits(empty.filter(x => x).length())
      }
      17 => names = Some(read_names(p, count))
      18 => created = read_times(p, count)
      19 => accessed = read_times(p, count)
      20 => modified = read_times(p, count)
      21 => {
        let defined = p.defined(count)
        if p.byte() != 0 {
          raise Unsupported(feature="external attributes")
        }
        attributes = []
        for present in defined {
          attributes.push(if present { Some(p.u32()) } else { None })
        }
      }
      25 =>
        for byte in p.take(p.data.length()) {
          if byte != b'\x00' {
            raise Invalid(offset=p.pos, reason="nonzero padding")
          }
        }
      _ =>
        raise Unsupported(
          feature="file property \{property}; input was not discarded",
        )
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
      let mode = (attr >> 16) & 0xf000U
      if (attr & 0x400U) != 0U ||
        (mode != 0U && mode != 0x8000U && mode != 0x4000U) {
        raise Unsupported(feature="link or special file: " + names[id])
      }
      if ((attr & 0x10U) != 0U) != (kind == Directory) ||
        (mode == 0x4000U && kind != Directory) ||
        (mode == 0x8000U && kind != File) {
        raise Invalid(
          offset=r.pos,
          reason="file kind disagrees with attributes",
        )
      }
    }
    entries.push({
      id,
      name: names[id],
      kind,
      size,
      crc32: crc,
      block,
      metadata: {
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
