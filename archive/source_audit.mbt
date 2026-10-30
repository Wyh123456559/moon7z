///|
/// Audit every positioned folder, continuing after typed archive/CRC failures.
/// Headers must already be valid. Raw source I/O errors propagate unchanged;
/// cancellation is never converted into a folder verdict. No payload is returned.
/// The existing audit schema retains every affected member and missing CRC.
pub async fn SourceArchive::audit(self : SourceArchive) -> AuditReport {
  let groups : Array[Array[Entry]] = Array::makei(
    self.streams.blocks.length(),
    _ => [],
  )
  let without_data : Array[Entry] = []
  let without_crc : Array[Entry] = []
  for entry in self.inventory {
    match entry.block {
      Some(id) => groups[id].push(entry)
      None => without_data.push(entry)
    }
    if entry.kind == File && entry.crc32 is None {
      without_crc.push(entry)
    }
  }
  let starts = source_pack_starts(self.streams)
  let results : Array[FolderAudit] = []
  for id, block in self.streams.blocks {
    let error : ArchiveError? = try {
      ignore(
        source_folder(
          self.source,
          self.streams,
          id,
          starts[id],
          self.limits,
          self.crypto,
        ),
      )
      None
    } catch {
      ArchiveError::_ as error => Some(error)
      error => raise error
    }
    results.push({ id, bytes: block.size, error, original: groups[id], })
  }
  { results, without_data, without_crc, }
}
