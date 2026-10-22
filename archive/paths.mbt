///|
/// A content-only export plan preserves names and original entry metadata.
/// It never renames, overwrites or merges colliding archive entries.
pub struct ContentPlan {
  priv folders : Array[String]
  priv inventory : Array[Entry]
}

///|
/// Directories appear once, with parents before children.
pub fn ContentPlan::directories(self : ContentPlan) -> Array[String] {
  self.folders.copy()
}

///|
/// Entries retain stable IDs and original metadata; returned arrays are copies.
pub fn ContentPlan::entries(self : ContentPlan) -> Array[Entry] {
  self.inventory.copy()
}

///|
/// Validate a portable relative path without normalization or rewriting.
/// Unicode is preserved. Additional filesystem-specific aliases must be checked
/// by exclusive creation in a new output tree, as the host exporter does.
pub fn validate_path(name : String) -> Unit raise ArchiveError {
  guard !name.is_empty() && name.length() <= 1024 else {
    raise UnsafePath(
      path=name,
      reason="empty path or more than 1024 UTF-16 units",
    )
  }
  let parts = name.split("/").collect()
  guard parts.length() <= 32 else {
    raise UnsafePath(path=name, reason="more than 32 path components")
  }
  for part in parts {
    guard !part.is_empty() &&
      part != "." &&
      part != ".." &&
      part.length() <= 200 else {
      raise UnsafePath(
        path=name,
        reason="empty, dot, parent or oversized component",
      )
    }
    if part.has_suffix(".") || part.has_suffix(" ") {
      raise UnsafePath(path=name, reason="component ends with a dot or space")
    }
    for char in part {
      if char.to_int() < 32 ||
        char == '\u007f' ||
        "\\<>:\"|?*".contains(char.to_string()) {
        raise UnsafePath(
          path=name,
          reason="control character, backslash or platform-reserved character",
        )
      }
    }
    let base = part.to_owned().split(".").next().unwrap().to_owned().to_lower()
    if ["con", "prn", "aux", "nul", "clock$", "conin$", "conout$"].contains(
        base,
      ) {
      raise UnsafePath(path=name, reason="Windows reserved device name")
    }
    for
      suffix in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³"] {
      if base == "com" + suffix || base == "lpt" + suffix {
        raise UnsafePath(path=name, reason="Windows reserved port name")
      }
    }
  }
}

///|
/// Check every member before the first filesystem write. This plan rejects
/// exact duplicates, ASCII case aliases and file/directory prefix conflicts.
pub fn Archive::plan_contents(self : Archive) -> ContentPlan raise ArchiveError {
  let nodes : Map[String, (String, EntryKind)] = Map([])
  let explicit : Set[String] = Set([])
  let folders : Array[String] = []
  for entry in self.inventory {
    validate_path(entry.name)
    guard !explicit.contains(entry.name) else {
      raise UnsafePath(path=entry.name, reason="duplicate archive entry")
    }
    explicit.add(entry.name)
    let parts = entry.name.split("/").collect()
    let mut prefix = ""
    for i, part in parts {
      prefix = if i == 0 {
        part.to_owned()
      } else {
        prefix + "/" + part.to_owned()
      }
      let kind = if i == parts.length() - 1 { entry.kind } else { Directory }
      let key = prefix.to_lower()
      if nodes.get(key) is Some((original, existing)) {
        guard original == prefix && existing == kind else {
          raise UnsafePath(
            path=entry.name,
            reason="case alias or file/directory collision at " + prefix,
          )
        }
      } else {
        nodes[key] = (prefix, kind)
        if kind == Directory {
          folders.push(prefix)
        }
      }
    }
  }
  { folders, inventory: self.inventory.copy(), }
}
