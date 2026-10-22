///|
/// Human-readable diagnostic with the failing scope and a corrective hint.
pub extend ArchiveError with Show::{to_string, output}

///|
pub impl Show for ArchiveError with fn output(self, logger) {
  match self {
    NoSuchEntry(id~) =>
      logger.write_string(
        "No 7z entry with ID \{id}. Select an ID from Archive::entries().",
      )
    UnsafePath(path~, reason~) =>
      logger.write_string(
        "Unsafe extraction path \{Repr(path)}: \{reason}. Rename the member before exporting.",
      )
    Invalid(offset~, reason~) =>
      logger.write_string(
        "Invalid 7z data at section byte \{offset}: \{reason}. Supply a complete, unmodified archive.",
      )
    Unsupported(feature~) =>
      logger.write_string(
        "Unsupported 7z feature: \{feature}. Repack without this feature or use a decoder that supports it.",
      )
    Limit(resource~, maximum~) =>
      logger.write_string(
        "7z resource limit exceeded: \{resource} (maximum \{maximum}). Increase the corresponding Limits value only for trusted, appropriately sized input.",
      )
    Checksum(scope~) =>
      logger.write_string(
        "7z CRC-32 mismatch in \{scope}. No verified result was returned; obtain an intact archive.",
      )
    Codec(reason~) =>
      logger.write_string(
        "7z decoder rejected compressed data: \{reason}. Check the archive with 7-Zip.",
      )
  }
}
