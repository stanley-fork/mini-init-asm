; timerfd helpers: create one-shot timer for grace period

global create_grace_timerfd
global read_timerfd_tick

%include "macros.inc"
%include "syscalls_amd64.inc"
extern g_verbose
extern log_prefix_num
extern get_timestamp_ptr
extern get_timestamp_ptr

section .text

; create_grace_timerfd(seconds) -> rax = fd or <0
; rdi=seconds (u64)
create_grace_timerfd:
    push r12
    push r13
    mov r13, rdi          ; save seconds
    ; debug: seconds == 0?
    test r13, r13
    jnz .have_secs
    LOG log_tfd_zero, log_tfd_zero_len
.have_secs:

    ; fd = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC|TFD_NONBLOCK)
    mov rdi, CLOCK_MONOTONIC
    mov rsi, TFD_CLOEXEC | TFD_NONBLOCK
    SYSCALL SYS_timerfd_create
    test rax, rax
    js .ret
    mov r12, rax          ; fd
    ; log timerfd fd number
    mov rdx, r12
    lea rdi, [rel log_tfd_prefix]
    mov rsi, log_tfd_prefix_len
    call log_prefix_num

    ; set itimerspec
    sub rsp, 32           ; __kernel_itimerspec (interval + value)
    ; it_interval = 0
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    ; it_value = seconds, 0 nsec
    mov [rsp+16], r13
    mov qword [rsp+24], 0

    ; timerfd_settime(fd, 0, &new_value, NULL)
    mov rdi, r12
    xor rsi, rsi          ; flags=0 (relative)
    mov rdx, rsp
    xor r10, r10          ; old_value=NULL
  .settime_retry:
    SYSCALL SYS_timerfd_settime
    test rax, rax
    jns .settime_ok
    mov rbx, rax
    neg rbx
    cmp rbx, EINTR
    je .settime_retry
    LOG log_tfd_set_err, log_tfd_set_err_len
    jmp .after_set
.settime_ok:
    LOG log_tfd_armed, log_tfd_armed_len

  .after_set:
    add rsp, 32
    mov rax, r12
.ret:
    pop r13
    pop r12
    ret

; read_timerfd_tick(fd): read u64 expirations to clear readiness
; rdi=fd, returns rax=0 on success or <0
read_timerfd_tick:
    sub rsp, 8
    mov rsi, rsp
    mov rdx, 8
    SYSCALL SYS_read
    add rsp, 8
    xor rax, rax
    ret

section .rodata
log_tfd_prefix:    db "DEBUG: timerfd created fd=", 0
log_tfd_prefix_len: equ $ - log_tfd_prefix - 1
log_tfd_armed:     db "DEBUG: grace timer armed", 10
log_tfd_armed_len: equ $ - log_tfd_armed
log_tfd_set_err:   db "ERROR: timerfd_settime failed", 10
log_tfd_set_err_len: equ $ - log_tfd_set_err
log_tfd_zero:      db "WARN: timer armed with 0 seconds", 10
log_tfd_zero_len:  equ $ - log_tfd_zero
