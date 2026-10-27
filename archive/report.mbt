///|
fn filetime_json(value : UInt64?) -> Json {
  match value {
    Some(value) => Json::string(value.to_string())
    None => Json::null()
  }
}

///|
/// Lossless metadata: raw FILETIME values are decimal strings, not floating
/// JSON numbers. Missing values are null, including a distinct numeric zero.
pub impl ToJson for Metadata with fn to_json(self) {
  {
    "start_position": filetime_json(self.start_position),
    "created_filetime": filetime_json(self.created),
    "accessed_filetime": filetime_json(self.accessed),
    "modified_filetime": filetime_json(self.modified),
    "attributes": match self.attributes {
      Some(value) => Json(value)
      None => Json::null()
    },
  }
}

///|
pub extend Metadata with ToJson::{to_json}

///|
/// Inventory entries retain archive order/IDs, original names and all metadata.
/// CRC-32 is eight lowercase hex digits or null; presence does not mean checked.
pub impl ToJson for Entry with fn to_json(self) {
  let crc : Json = match self.crc32 {
    None => Json::null()
    Some(value) => {
      let hex = value.to_string(radix=16)
      Json::string("0".repeat(8 - hex.length()) + hex)
    }
  }
  {
    "id": Json(self.id),
    "anti": Json(self.anti),
    "semantics": Json(self.semantics().json_name()),
    "name": Json(self.name),
    "kind": Json::string(
      match self.kind {
        File => "file"
        Directory => "directory"
      },
    ),
    "size": Json(self.size),
    "crc32": crc,
    "block": match self.block {
      Some(id) => Json(id)
      None => Json::null()
    },
    "metadata": self.metadata.to_json(),
  }
}

///|
pub extend Entry with ToJson::{to_json}

///|
/// Produce a fresh inventory document without decoding payloads. The explicit
/// false flag describes this operation even if the caller previously verified.
pub fn Archive::inventory_json(self : Archive) -> Json {
  {
    "schema": "moon7z.inventory.v1",
    "contents_verified": false,
    "entries": Json::array(self.inventory.map(entry => entry.to_json())),
    "archive_properties": Json::array(
      self.archive_properties.map(property => property.to_json()),
    ),
    "metadata_streams": metadata_streams_json(self.auxiliary),
    "file_properties": Json::array(
      self.file_extensions.map(property => property.to_json()),
    ),
  }
}

///|
/// A report is only obtainable after successful whole-archive verification.
/// Counts distinguish checked CRCs from missing ones; CRC is not authentication.
pub impl ToJson for Verification with fn to_json(self) {
  {
    "schema": "moon7z.verification.v1",
    "contents_verified": true,
    "files": Json(self.files),
    "bytes": Json(self.bytes),
    "blocks": Json(self.blocks),
    "member_crcs_checked": Json(self.member_crcs_checked),
    "members_without_crc": Json(self.members_without_crc),
  }
}

///|
pub extend Verification with ToJson::{to_json}
