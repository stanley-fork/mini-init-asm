.include "syscalls_aarch64.inc"
.include "macros_arm64.inc"

.text
.align 2
.global create_grace_timerfd
.global read_timerfd_tick
.extern g_verbose
.extern log_prefix_num
.extern get_timestamp_ptr

create_grace_timerfd:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!

    mov x19, x0                 // seconds
    mov x0, CLOCK_MONOTONIC
    mov x1, #TFD_CLOEXEC
    mov x2, #TFD_NONBLOCK
    orr x1, x1, x2
    SYSCALL SYS_timerfd_create
    cmp x0, #0
    blt .ret                    // error
    mov x20, x0                 // fd

    // log creation
    mov x2, x20
    adrp x0, log_tfd_prefix
    add x0, x0, :lo12:log_tfd_prefix
    mov x1, #log_tfd_prefix_len
    bl log_prefix_num

    sub sp, sp, #32
    mov x2, #0
    str x2, [sp]                // interval sec
    str x2, [sp, #8]            // interval nsec
    str x19, [sp, #16]          // value sec
    str x2, [sp, #24]           // value nsec

    mov x0, x20
    mov x1, #0
    mov x2, sp
    mov x3, #0
.settime_retry:
    SYSCALL SYS_timerfd_settime
    cmp x0, #0
    bge .settime_ok
    neg x4, x0
    cmp x4, #4                  // EINTR
    beq .settime_retry
    LOG log_tfd_err, log_tfd_err_len
    b .after_set
.settime_ok:
    LOG log_tfd_armed, log_tfd_armed_len
.after_set:
    add sp, sp, #32
    mov x0, x20
.ret:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

read_timerfd_tick:
    sub sp, sp, #8
    mov x1, sp
    mov x2, #8
1:
    SYSCALL SYS_read
    cmp x0, #8
    beq 2f
    cmp x0, #0
    bgt 3f
    beq 4f
    neg x4, x0
    cmp x4, #EINTR
    beq 1b
    cmp x4, #EAGAIN
    beq 2f              // already drained
    b 5f
2:
    mov x0, #0
    b 6f
3:  // short read
4:  // eof
    mov x0, #-1
    b 6f
5:
    // keep negative errno in x0
6:
    add sp, sp, #8
    ret

.section .rodata
log_tfd_prefix:    .asciz "DEBUG: timerfd created fd="
.equ log_tfd_prefix_len, . - log_tfd_prefix - 1
log_tfd_armed:     .asciz "DEBUG: grace timer armed"
.equ log_tfd_armed_len, . - log_tfd_armed - 1
log_tfd_err:       .asciz "ERROR: timerfd_settime failed"
.equ log_tfd_err_len, . - log_tfd_err - 1
