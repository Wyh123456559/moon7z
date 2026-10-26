///|
pub(all) enum ChangeKind {
  Added
  Removed
  TypeChanged
  ContentChanged
  MetadataChanged
  ContentAndMetadataChanged
} derive(Eq, Debug)

///|
pub struct EntryChange {
  name : String
  kind : ChangeKind
  left : Entry?
  right : Entry?
} derive(Eq, Debug)

///|
/// A comparison is only returned after both archives pass available CRC checks.
pub struct Comparison {
  priv differences : Array[EntryChange]
  priv left_report : Verification
  priv right_report : Verification
  priv before_properties : Array[ArchiveProperty]
  priv after_properties : Array[ArchiveProperty]
}

///|
pub fn Comparison::changes(self : Comparison) -> Array[EntryChange] {
  self.differences.copy()
}

///|
pub fn Comparison::identical(self : Comparison) -> Bool {
  self.differences.is_empty() && !self.archive_properties_changed()
}

///|
pub fn Comparison::archive_properties_changed(self : Comparison) -> Bool {
  self.before_properties != self.after_properties
}

///|
fn unique_names(archive : Archive) -> Map[String, Entry] raise ArchiveError {
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
/// Compare exact original names, kinds, decoded bytes and all retained metadata.
/// Compression, solid layout, member IDs and CRC presence are not content
/// changes. Duplicate names are ambiguous and refused on either side. Both
/// archives are fully verified even for added/removed files. Successful changes
/// are ordered lexically by UTF-16 units, without path or Unicode normalization.
pub fn Archive::compare(
  self : Archive,
  other : Archive,
) -> Comparison raise ArchiveError {
  let left = unique_names(self)
  let right = unique_names(other)
  let left_report = self.verify()
  let right_report = other.verify()
  let left_reader = self.reader()
  let right_reader = other.reader()
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
        if a.kind != b.kind {
          TypeChanged
        } else {
          let content = a.kind == File &&
            left_reader.read(a.id).bytes != right_reader.read(b.id).bytes
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
  }
}

///|
pub impl ToJson for EntryChange with fn to_json(self) {
  let kind = match self.kind {
    Added => "added"
    Removed => "removed"
    TypeChanged => "type_changed"
    ContentChanged => "content_changed"
    MetadataChanged => "metadata_changed"
    ContentAndMetadataChanged => "content_and_metadata_changed"
  }
  {
    "name": Json(self.name),
    "kind": Json(kind),
    "left": match self.left {
      Some(entry) => entry.to_json()
      None => Json::null()
    },
    "right": match self.right {
      Some(entry) => entry.to_json()
      None => Json::null()
    },
  }
}

///|
pub extend EntryChange with ToJson::{to_json}

///|
pub impl ToJson for Comparison with fn to_json(self) {
  {
    "schema": "moon7z.comparison.v1",
    "identical": Json(self.identical()),
    "left_verification": self.left_report.to_json(),
    "right_verification": self.right_report.to_json(),
    "changes": Json::array(self.differences.map(change => change.to_json())),
    "archive_properties_changed": Json(self.archive_properties_changed()),
    "left_archive_properties": Json::array(
      self.before_properties.map(property => property.to_json()),
    ),
    "right_archive_properties": Json::array(
      self.after_properties.map(property => property.to_json()),
    ),
  }
}

///|
pub extend Comparison with ToJson::{to_json}

///|
#deprecated
pub extend ChangeKind with Eq::{equal, not_equal}

///|
#deprecated
pub extend ChangeKind with @debug.Debug::{to_repr}

///|
#deprecated
pub extend EntryChange with Eq::{equal, not_equal}

///|
#deprecated
pub extend EntryChange with @debug.Debug::{to_repr}
