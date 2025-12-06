.include "syscalls_aarch64.inc"

.text
.align 2
.global _start

// Simple long-running process that sleeps in a loop
// It will terminate with default action on TERM when run under mini-init
_start:
    sub sp, sp, #16          // reserve space for struct timespec
    mov x3, #1000            // tv_sec = 1000
    str x3, [sp]             // store tv_sec (low 8 bytes)
    mov x3, #0               // tv_nsec = 0
    str x3, [sp, #8]

.sleep_loop:
    mov x0, sp               // req
    mov x1, #0               // rem = NULL
    mov x8, #SYS_nanosleep
    svc #0
    b .sleep_loop
