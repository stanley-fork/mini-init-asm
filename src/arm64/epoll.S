.include "syscalls_aarch64.inc"
.include "macros_arm64.inc"

.bss
.align 3
epoll_events_buf:
    .skip EPOLL_EVENT_SIZE * 4

.text
.align 2
.global epoll_create_fd
.global epoll_add_fd
.global epoll_wait_once
.extern g_verbose
.extern log_prefix_num
.extern get_timestamp_ptr

epoll_create_fd:
    mov x0, #0
    SYSCALL SYS_epoll_create1
    cmp x0, #0
    blt .ret
    mov x2, x0
    adrp x0, log_epfd_prefix
    add x0, x0, :lo12:log_epfd_prefix
    mov x1, #log_epfd_prefix_len
    bl log_prefix_num
.ret:
    ret

epoll_add_fd:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!

    LOG log_epoll_add_enter, log_epoll_add_enter_len

    mov x19, x0      // epfd
    mov x20, x1      // fd
    sub sp, sp, #EPOLL_EVENT_SIZE
    mov w2, #EPOLLIN
    str w2, [sp]
    str x20, [sp, #8]

    mov x0, x19
    mov x1, #EPOLL_CTL_ADD
    mov x2, x20
    mov x3, sp
.ctl_retry:
    SYSCALL SYS_epoll_ctl
    cmp x0, #0
    bge .ctl_ok
    neg x4, x0
    cmp x4, #4       // EINTR
    beq .ctl_retry
    LOG log_epoll_ctl_err, log_epoll_ctl_err_len
    mov x0, #-1
    b .ctl_out
.ctl_ok:
    mov x2, x20
    adrp x0, log_epoll_add_prefix
    add x0, x0, :lo12:log_epoll_add_prefix
    mov x1, #log_epoll_add_prefix_len
    bl log_prefix_num
    mov x0, #0
.ctl_out:
    add sp, sp, #EPOLL_EVENT_SIZE
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    LOG log_epoll_add_exit, log_epoll_add_exit_len
    ret

epoll_wait_once:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!

    adrp x1, epoll_events_buf
    add x1, x1, :lo12:epoll_events_buf
    mov x2, #4
    mov x3, #-1
    mov x4, #0
    mov x5, #0
.wait_retry:
    SYSCALL SYS_epoll_pwait
    cmp x0, #0
    bge .check_count
    neg x19, x0
    cmp x19, #4
    beq .wait_retry
    LOG log_epoll_wait_err, log_epoll_wait_err_len
    mov x0, #-1
    b .wait_out
.check_count:
    cmp x0, #1
    blt .err
    ldr x0, [x1, #8]
    b .wait_out
.err:
    mov x0, #-1
.wait_out:
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

.section .rodata
log_epfd_prefix:      .asciz "DEBUG: epoll fd created fd="
.equ log_epfd_prefix_len, . - log_epfd_prefix - 1
log_epoll_add_prefix: .asciz "DEBUG: added FD to epoll fd="
.equ log_epoll_add_prefix_len, . - log_epoll_add_prefix - 1
log_epoll_add_enter:  .asciz "DEBUG: epoll_add_fd enter"
.equ log_epoll_add_enter_len, . - log_epoll_add_enter - 1
log_epoll_add_exit:   .asciz "DEBUG: epoll_add_fd exit"
.equ log_epoll_add_exit_len, . - log_epoll_add_exit - 1
log_epoll_ctl_err:    .asciz "ERROR: epoll_ctl failed"
.equ log_epoll_ctl_err_len, . - log_epoll_ctl_err - 1
log_epoll_wait_err:   .asciz "ERROR: epoll_pwait failed"
.equ log_epoll_wait_err_len, . - log_epoll_wait_err - 1
