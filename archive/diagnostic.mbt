///|
/// Human-readable diagnostic with the failing scope and a corrective hint.
pub extend ArchiveError with Show::{to_string, output}

///|
pub impl Show for ArchiveError with fn output(self, logger) {
  match self {
    SourceSignatureNotFound(searched_bytes~) =>
      logger.write_string(
        "No CRC-valid 7z start header among the first \{searched_bytes} eligible source offsets. Check the input, increase search_bytes for a larger stub, or use SourceEmbeddedArchive::open_at with a known offset.",
      )
    SourceLimit(resource~, maximum~) =>
      logger.write_string(
        "Source policy limit: \{resource} exceeds \{maximum} bytes. Raise the explicit source/total-output policy only for trusted inputs.",
      )
    SourceRead(offset~, reason~) =>
      logger.write_string(
        "Source read at byte \{offset}: \{reason}. Supply an exact, stable seekable source and check the configured source/read limits.",
      )
    VolumeError(index~, reason~) =>
      logger.write_string(
        "Volume input at list index \{index}: \{reason}. Supply every volume in numeric order, starting with .001 (or its original zero/one-based padding); finish downloading before reading.",
      )
    SignatureNotFound(searched_bytes~) =>
      logger.write_string(
        "No CRC-valid 7z start header among the first \{searched_bytes} eligible input offsets. Check the input, increase search_bytes for a trusted larger stub, or use EmbeddedArchive::open_at with a known offset.",
      )
    PasswordRequired =>
      logger.write_string(
        "This 7z stream requires a password. Supply Archive::open(password=...) or the CLI --password-env option.",
      )
    DecryptionFailed =>
      logger.write_string(
        "Encrypted 7z data failed decoding or integrity checks. Check the password and obtain an intact archive; these causes cannot be distinguished reliably.",
      )
    AmbiguousName(name~, first_id~, second_id~) =>
      logger.write_string(
        "Ambiguous 7z name \{Repr(name)} at IDs \{first_id} and \{second_id}. Name-based comparison requires unique original names; inspect entries by ID instead.",
      )
    MissingChecksum(id~, name~) =>
      logger.write_string(
        "7z entry \{id} (\{Repr(name)}) has no member CRC-32. Repack with member checksums or explicitly use the default available-checks policy.",
      )
    InvalidRange(id~, offset~, length~, size~) =>
      logger.write_string(
        "Invalid byte range for 7z entry \{id}: offset \{offset}, length \{length}, file size \{size}. Use nonnegative values within the member; an empty range at EOF is allowed.",
      )
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
