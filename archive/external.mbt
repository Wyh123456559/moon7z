///|
fn Cursor::external(
  self : Cursor,
  buffers : Array[Bytes],
) -> (Cursor, Bool) raise ArchiveError {
  match self.byte() {
    0 => (self, false)
    1 => {
      let index = self.number()
      guard index < buffers.length().to_uint64() else {
        raise Invalid(
          offset=self.pos,
          reason="external metadata stream index is unavailable",
        )
      }
      (Cursor::new(buffers[index.to_int()]), true)
    }
    _ =>
      raise Invalid(
        offset=self.pos - 1,
        reason="invalid external metadata flag",
      )
  }
}

///|
/// Original decoded additional-stream buffers in folder order. Immutable bytes
/// and a detached array preserve both referenced and unreferenced metadata.
pub fn Archive::metadata_streams(self : Archive) -> Array[Bytes] {
  self.auxiliary.copy()
}

///|
fn metadata_streams_json(buffers : Array[Bytes]) -> Json {
  Json::array(
    buffers.mapi((id, data) => {
      "id": Json(id),
      "data_base64": Json(@base64.encode(data)),
    }),
  )
}

///|
fn decode_metadata_streams(
  input : Bytes,
  streams : Streams,
  limits : Limits,
  crypto : CryptState,
) -> Array[Bytes] raise ArchiveError {
  let decoded = decode_streams(input, streams, limits, crypto=Some(crypto))
  for i, block in streams.blocks {
    let mut start = 0
    for (size, crc) in block.pieces {
      check_crc(decoded[i][start:start + size], crc, "metadata substream") catch {
        error => raise encrypted_error(block, error)
      }
      start += size
    }
  }
  decoded
}

///|
fn packed_region(streams : Streams) -> (UInt64, UInt64) {
  let start = 32UL + streams.pack_offset
  let mut end = start
  for size in streams.pack_sizes {
    end += size.to_uint64()
  }
  (start, end)
}

///|
fn check_regions(
  regions : Array[(UInt64, UInt64)],
  boundary : UInt64,
) -> Unit raise ArchiveError {
  let sorted = regions.filter(region => region.0 != region.1)
  sorted.sort_by((a, b) => {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  let mut end = 32UL
  for (start, limit) in sorted {
    guard start >= end else {
      raise position_error(start, "packed metadata/data regions overlap")
    }
    guard start == end else {
      raise Unsupported(
        feature="unclaimed bytes or gaps before packed data/header",
      )
    }
    end = limit
  }
  guard end == boundary else {
    raise Unsupported(
      feature="unclaimed bytes or gaps before packed data/header",
    )
  }
}
