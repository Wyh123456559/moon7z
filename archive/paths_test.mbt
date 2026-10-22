///|
test "portable paths preserve Unicode and ordinary relative names" {
  for
    name in [
      "data.json", "assets/image.png", "中文/清单.json", "a b/c", "file.tar.gz",
      "COM10.txt",
    ] {
    @archive.validate_path(name)
  }
}

///|
test "portable paths reject traversal absolute paths devices and aliases" {
  for
    name in [
      "", "/etc/passwd", "../a", "a/../b", "./a", "a//b", "a/", "C:/a", "a\\b", "\\\\server\\share",
      "a:stream", "nul.txt", "CON", "conin$", "LPT9.log", "COM¹", "a.", "a ", "a/ b.",
      "a\n.txt", "a\u007f", "a?b", "a*b", "a|b", "a\"b", "a<b", "a>b",
    ] {
    let rejected = try {
      @archive.validate_path(name)
      false
    } catch {
      @archive.UnsafePath(..) => true
      _ => false
    }
    assert_true(rejected, msg=name)
  }
}

///|
test "path length component and nesting limits are explicit" {
  @archive.validate_path("a".repeat(200))
  for name in ["a".repeat(201), "a/".repeat(32) + "a", "a".repeat(1025)] {
    let rejected = try {
      @archive.validate_path(name)
      false
    } catch {
      @archive.UnsafePath(..) => true
      _ => false
    }
    assert_true(rejected)
  }
}
