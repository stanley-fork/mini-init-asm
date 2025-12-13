.include "syscalls_aarch64.inc"
.include "macros_arm64.inc"

.text
.align 2
.global log_prefix_num
.extern g_verbose

log_prefix_num:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    adrp x19, g_verbose
    add x19, x19, :lo12:g_verbose
    ldr x19, [x19]
    cbz x19, .out

    mov x20, x0          // prefix ptr
    mov x21, x1          // prefix len
    mov x22, x2          // value

    mov x0, #2
    mov x1, x20
    mov x2, x21
    SYSCALL SYS_write

    sub sp, sp, #32
    add x23, sp, #32
    mov x24, #0          // length
    mov x25, x23         // current ptr
    mov x26, #10
    mov x0, x22
    cbnz x0, .conv_loop

    sub x25, x25, #1
    mov w27, #'0'
    strb w27, [x25]
    mov x24, #1
    b .have_num

.conv_loop:
    udiv x28, x0, x26
    mul x27, x28, x26
    sub x27, x0, x27
    add w27, w27, #'0'
    sub x25, x25, #1
    strb w27, [x25]
    add x24, x24, #1
    mov x0, x28
    cbnz x0, .conv_loop

.have_num:
    mov x0, #2
    mov x1, x25
    mov x2, x24
    SYSCALL SYS_write

    mov x0, #2
    adrp x1, ln_char
    add x1, x1, :lo12:ln_char
    mov x2, #1
    SYSCALL SYS_write

    add sp, sp, #32

.out:
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

.section .rodata
.align 2
ln_char:
    .byte 0x0a
