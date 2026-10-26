///|
/// A folder verdict, not recovered payload data. Bytes is the declared size.
pub struct FolderAudit {
  id : Int32
  bytes : Int32
  error : ArchiveError?
  priv original : Array[Entry]
}

///|
pub fn FolderAudit::entries(self : FolderAudit) -> Array[Entry] {
  self.original.copy()
}

///|
pub fn FolderAudit::passed(self : FolderAudit) -> Bool {
  self.error is None
}

///|
pub struct AuditReport {
  priv results : Array[FolderAudit]
  priv without_data : Array[Entry]
  priv without_crc : Array[Entry]
}

///|
pub fn AuditReport::folders(self : AuditReport) -> Array[FolderAudit] {
  self.results.copy()
}

///|
pub fn AuditReport::entries_without_data(self : AuditReport) -> Array[Entry] {
  self.without_data.copy()
}

///|
pub fn AuditReport::files_without_crc(self : AuditReport) -> Array[Entry] {
  self.without_crc.copy()
}

///|
/// Missing CRCs are reported separately and do not count as failed checks.
pub fn AuditReport::all_available_checks_passed(self : AuditReport) -> Bool {
  self.results.all(result => result.passed())
}

///|
/// Inspect every folder, continuing after typed payload/CRC failures. Headers
/// must already have passed Archive::open. No payload bytes are returned or
/// written. Unstreamed entries and missing member CRCs remain explicit. Each
/// decoded folder is discarded after checking; this is not partial extraction.
pub fn Archive::audit(self : Archive) -> AuditReport {
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
  let results : Array[FolderAudit] = []
  let mut start = 32 + self.streams.pack_offset
  for id, block in self.streams.blocks {
    let error : ArchiveError? = try {
      verify_folder(self, id, start, groups[id])
      None
    } catch {
      err => Some(err)
    }
    results.push({ id, bytes: block.size, error, original: groups[id], })
    start += packed_folder_bytes(self.streams, id)
  }
  { results, without_data, without_crc, }
}

///|
pub impl ToJson for FolderAudit with fn to_json(self) {
  {
    "id": Json(self.id),
    "bytes": Json(self.bytes),
    "status": Json(if self.passed() { "passed" } else { "failed" }),
    "entries": Json::array(self.original.map(entry => entry.to_json())),
    "error": match self.error {
      Some(error) => error.to_json()
      None => Json::null()
    },
  }
}

///|
pub extend FolderAudit with ToJson::{to_json}

///|
pub impl ToJson for AuditReport with fn to_json(self) {
  {
    "schema": "moon7z.audit.v1",
    "all_available_checks_passed": Json(self.all_available_checks_passed()),
    "folders": Json::array(self.results.map(result => result.to_json())),
    "entries_without_data": Json::array(
      self.without_data.map(entry => entry.to_json()),
    ),
    "files_without_crc": Json::array(
      self.without_crc.map(entry => entry.to_json()),
    ),
  }
}

///|
pub extend AuditReport with ToJson::{to_json}
