.include "syscalls_aarch64.inc"
.include "macros_arm64.inc"

.extern g_exit_code_base

.bss
.align 3
wait_status:
    .skip 8

.text
.align 2
.global reap_children_nonblock
.global extract_exit_code
.global get_wait_status_ptr
.global wait_status

reap_children_nonblock:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!

    mov x19, #0
.again:
    mov x0, #-1
    adrp x1, wait_status
    add x1, x1, :lo12:wait_status
    mov x2, #1          // WNOHANG
    mov x3, #0
    SYSCALL SYS_wait4
    cmp x0, #0
    bgt .got
    beq .done_reap
    b .done_reap

.got:
    mov x19, x0
    b .again

.done_reap:
    mov x0, x19
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

get_wait_status_ptr:
    adrp x0, wait_status
    add x0, x0, :lo12:wait_status
    ret

// Given status in x0 -> exit code
extract_exit_code:
    and x1, x0, #0x7f
    cbz x1, .normal
    adrp x2, g_exit_code_base
    add x2, x2, :lo12:g_exit_code_base
    ldr x2, [x2]
    add x0, x1, x2
    ret
.normal:
    lsr x0, x0, #8
    and x0, x0, #0xff
    ret
