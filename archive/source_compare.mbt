///|
/// A fully verified comparison of decoded archives, not physical container or
/// SFX envelope bytes. Verification totals remain UInt64. No extraction occurs.
pub struct SourceComparison {
  priv differences : Array[EntryChange]
  priv left_report : SourceVerification
  priv right_report : SourceVerification
  priv before_properties : Array[ArchiveProperty]
  priv after_properties : Array[ArchiveProperty]
  priv before_streams : Array[Bytes]
  priv after_streams : Array[Bytes]
  priv before_file_properties : Array[FileProperty]
  priv after_file_properties : Array[FileProperty]
}

///|
pub fn SourceComparison::changes(self : SourceComparison) -> Array[EntryChange] {
  self.differences.copy()
}

///|
pub fn SourceComparison::archive_properties_changed(
  self : SourceComparison,
) -> Bool {
  self.before_properties != self.after_properties
}

///|
pub fn SourceComparison::metadata_streams_changed(
  self : SourceComparison,
) -> Bool {
  self.before_streams != self.after_streams
}

///|
pub fn SourceComparison::file_properties_changed(
  self : SourceComparison,
) -> Bool {
  self.before_file_properties != self.after_file_properties
}

///|
pub fn SourceComparison::identical(self : SourceComparison) -> Bool {
  self.differences.is_empty() &&
  !self.archive_properties_changed() &&
  !self.metadata_streams_changed() &&
  !self.file_properties_changed()
}

///|
fn source_unique_names(
  archive : SourceArchive,
) -> Map[String, Entry] raise ArchiveError {
  let result : Map[String, Entry] = Map([])
  for entry in archive.inventory {
    if result.get(entry.name) is Some(previous) {
      raise AmbiguousName(
        name=entry.name,
        first_id=previous.id,
        second_id=entry.id,
      )
    }
    result[entry.name] = entry
  }
  result
}

///|
fn source_comparison_reader(
  archive : SourceArchive,
) -> SourceReader raise ArchiveError {
  let mut maximum = 0
  for block in archive.streams.blocks {
    maximum = maximum.max(block.size)
  }
  archive.reader(cache_bytes=maximum)
}

///|
/// Both archives pass all available CRC checks before any result is returned,
/// including added/removed members. Duplicate original names fail before payload
/// I/O. Files compare actual bytes in 64 KiB copies, never CRC equality alone.
/// Two readers retain at most one bounded decoded folder per side. Inputs must
/// remain stable and open throughout; this cannot establish an atomic snapshot.
pub async fn SourceArchive::compare(
  self : SourceArchive,
  other : SourceArchive,
  require_member_crcs~ : Bool = false,
) -> SourceComparison {
  let left = source_unique_names(self)
  let right = source_unique_names(other)
  let left_report = self.verify(require_member_crcs~)
  let right_report = other.verify(require_member_crcs~)
  let left_reader = source_comparison_reader(self)
  let right_reader = source_comparison_reader(other)
  let names : Array[String] = []
  let seen : Set[String] = Set([])
  for archive in [self, other] {
    for entry in archive.inventory {
      if !seen.contains(entry.name) {
        seen.add(entry.name)
        names.push(entry.name)
      }
    }
  }
  names.sort_by((a, b) => a.lexical_compare(b))
  let differences : Array[EntryChange] = []
  for name in names {
    let before = left.get(name)
    let after = right.get(name)
    let kind = match (before, after) {
      (None, Some(_)) => Added
      (Some(_), None) => Removed
      (Some(a), Some(b)) =>
        if a.kind != b.kind ||
          a.anti != b.anti ||
          a.semantics() != b.semantics() {
          TypeChanged
        } else {
          let mut content = a.kind == File && a.size != b.size
          if a.kind == File && !content {
            let mut offset = 0
            while offset < a.size {
              let length = (a.size - offset).min(65536)
              let first = left_reader.read_range(a.id, offset~, length~)
              let second = right_reader.read_range(b.id, offset~, length~)
              if first != second {
                content = true
                break
              }
              offset += length
            }
          }
          let metadata = a.metadata != b.metadata
          if content && metadata {
            ContentAndMetadataChanged
          } else if content {
            ContentChanged
          } else if metadata {
            MetadataChanged
          } else {
            continue
          }
        }
      (None, None) => continue
    }
    differences.push({ name, kind, left: before, right: after, })
  }
  {
    differences,
    left_report,
    right_report,
    before_properties: self.properties(),
    after_properties: other.properties(),
    before_streams: self.metadata_streams(),
    after_streams: other.metadata_streams(),
    before_file_properties: self.file_properties(),
    after_file_properties: other.file_properties(),
  }
}

///|
pub impl ToJson for SourceComparison with fn to_json(self) {
  {
    "schema": "moon7z.source_comparison.v1",
    "scope": "decoded_archive_contents_and_metadata",
    "identical": Json(self.identical()),
    "left_verification": self.left_report.to_json(),
    "right_verification": self.right_report.to_json(),
    "changes": Json::array(self.differences.map(change => change.to_json())),
    "archive_properties_changed": Json(self.archive_properties_changed()),
    "metadata_streams_changed": Json(self.metadata_streams_changed()),
    "file_properties_changed": Json(self.file_properties_changed()),
    "left_file_properties": Json::array(
      self.before_file_properties.map(property => property.to_json()),
    ),
    "right_file_properties": Json::array(
      self.after_file_properties.map(property => property.to_json()),
    ),
    "left_metadata_streams": metadata_streams_json(self.before_streams),
    "right_metadata_streams": metadata_streams_json(self.after_streams),
    "left_archive_properties": Json::array(
      self.before_properties.map(property => property.to_json()),
    ),
    "right_archive_properties": Json::array(
      self.after_properties.map(property => property.to_json()),
    ),
  }
}

///|
pub extend SourceComparison with ToJson::{to_json}
