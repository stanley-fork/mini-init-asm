// Common macros & helpers for Linux AArch64 syscalls

.macro SYSCALL num
    mov x8, \num
    svc #0
.endm

.macro WRITE fd, ptr, len
    mov x0, \fd
    mov x1, \ptr
    mov x2, \len
    SYSCALL SYS_write
.endm

.macro EXIT code
    mov x0, \code
    SYSCALL SYS_exit
.endm

.macro LOG msg_ptr, msg_len
    stp x0, x1, [sp, #-16]!
    stp x2, x3, [sp, #-16]!
    adrp x3, g_verbose
    add x3, x3, :lo12:g_verbose
    ldr x3, [x3]
    cbz x3, 1f
    bl get_timestamp_ptr
    mov x1, x0
    mov x0, #2
    mov x2, #19
    SYSCALL SYS_write
    mov x0, #2
    adrp x1, \msg_ptr
    add x1, x1, :lo12:\msg_ptr
    mov x2, #\msg_len
    SYSCALL SYS_write
1:
    ldp x2, x3, [sp], #16
    ldp x0, x1, [sp], #16
.endm
