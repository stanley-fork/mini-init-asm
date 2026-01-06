.include "syscalls_aarch64.inc"
.include "macros_arm64.inc"

.section .rodata
.align 2

log_before_clone:
    .asciz "DEBUG: spawn before clone"
    .equ log_before_clone_len, . - log_before_clone - 1
log_after_clone_parent:
    .asciz "DEBUG: spawn clone parent"
    .equ log_after_clone_parent_len, . - log_after_clone_parent - 1
log_after_clone_child:
    .asciz "DEBUG: spawn clone child"
    .equ log_after_clone_child_len, . - log_after_clone_child - 1

.text
.align 2
.global do_spawn
.type do_spawn, %function

do_spawn:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!

    mov x19, x0      // argv_exec
    mov x20, x1      // envp

    LOG log_before_clone, log_before_clone_len
    // clone(flags=SIGCHLD, child_stack=NULL to mimic fork semantics)
    mov x0, #SIGCHLD
    mov x1, #0            // child_stack = NULL -> kernel provides
    mov x2, #0
    mov x3, #0
    mov x4, #0
    SYSCALL SYS_clone
    cmp x0, #0
    bgt .parent
    beq .child
    b .out_restore

.parent:
    LOG log_after_clone_parent, log_after_clone_parent_len
    // x0 already pid
    b .out_restore

.child:
    LOG log_after_clone_child, log_after_clone_child_len
    // Unblock all signals in child (so TERM/INT etc are delivered)
    sub sp, sp, #16
    mov x1, #0
    str x1, [sp]
    mov x0, #SIG_SETMASK
    mov x1, sp           // empty mask
    mov x2, #0
    mov x3, #8
    SYSCALL SYS_rt_sigprocmask
    add sp, sp, #16

    mov x0, #0
    SYSCALL SYS_setsid

    mov x0, #0
    mov x1, #0
    SYSCALL SYS_setpgid

    ldr x0, [x19]
    mov x1, x19
    mov x2, x20
    SYSCALL SYS_execve

    mov x0, #127
    SYSCALL SYS_exit

.out_restore:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
.out:
    ret
