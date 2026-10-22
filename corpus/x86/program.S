/* Apache-2.0. A freestanding Linux x86-64 fixture; no C runtime is linked. */
.global _start
.text
_start:
    call emit
    mov $60, %eax
    xor %edi, %edi
    syscall
emit:
    mov $1, %eax
    mov $1, %edi
    lea message(%rip), %rsi
    mov $19, %edx
    syscall
    ret
.section .rodata
message:
    .ascii "moon7z x86 fixture\n"
.section .note.GNU-stack,"",@progbits
