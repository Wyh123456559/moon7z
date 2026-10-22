///|
/// A typed diagnostic preserves machine-readable fields plus the corrective
/// human message. This is used in audit reports; it is not a success result.
pub impl ToJson for ArchiveError with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  match self {
    Invalid(offset~, reason~) => {
      fields["code"] = Json("invalid")
      fields["offset"] = Json(offset)
      fields["reason"] = Json(reason)
    }
    Unsupported(feature~) => {
      fields["code"] = Json("unsupported")
      fields["feature"] = Json(feature)
    }
    Limit(resource~, maximum~) => {
      fields["code"] = Json("limit")
      fields["resource"] = Json(resource)
      fields["maximum"] = Json(maximum)
    }
    Checksum(scope~) => {
      fields["code"] = Json("checksum")
      fields["scope"] = Json(scope)
    }
    Codec(reason~) => {
      fields["code"] = Json("codec")
      fields["reason"] = Json(reason)
    }
    UnsafePath(path~, reason~) => {
      fields["code"] = Json("unsafe_path")
      fields["path"] = Json(path)
      fields["reason"] = Json(reason)
    }
    NoSuchEntry(id~) => {
      fields["code"] = Json("no_such_entry")
      fields["id"] = Json(id)
    }
    InvalidRange(id~, offset~, length~, size~) => {
      fields["code"] = Json("invalid_range")
      fields["id"] = Json(id)
      fields["offset"] = Json(offset)
      fields["length"] = Json(length)
      fields["size"] = Json(size)
    }
    MissingChecksum(id~, name~) => {
      fields["code"] = Json("missing_checksum")
      fields["id"] = Json(id)
      fields["name"] = Json(name)
    }
    AmbiguousName(name~, first_id~, second_id~) => {
      fields["code"] = Json("ambiguous_name")
      fields["name"] = Json(name)
      fields["first_id"] = Json(first_id)
      fields["second_id"] = Json(second_id)
    }
  }
  fields["message"] = Json(self.to_string())
  Json::object(fields)
}

///|
pub extend ArchiveError with ToJson::{to_json}
