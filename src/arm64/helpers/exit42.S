.include "syscalls_aarch64.inc"

.text
.align 2
.global _start

_start:
    // Exit with status 42
    mov x0, #42
    mov x8, #SYS_exit
    svc #0
