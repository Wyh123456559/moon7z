///|
test "real RISC-V archives restore JAL AUIPC escapes offsets solid and separate folders" {
  for
    (bytes, blocks) in [
      (riscv_copy, 1),
      (riscv_lzma2, 1),
      (riscv_offset, 1),
      (riscv_wrap, 1),
      (riscv_separate, 2),
    ] {
    let archive = @archive.Archive::open(bytes)
    assert_eq(archive.verify().blocks, blocks)
    assert_eq(archive.verify().bytes, 61445)
    for item in archive.extract_all() {
      assert_eq(
        item.bytes,
        if item.entry.name == "a-head.bin" {
          riscv_head
        } else {
          riscv_tail
        },
      )
    }
    assert_true(archive.audit().all_available_checks_passed())
    assert_true(archive.compare(@archive.Archive::open(riscv_copy)).identical())
  }
}
