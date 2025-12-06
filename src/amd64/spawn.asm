; fork -> child: setsid + setpgid(0,0) -> execve(argv_exec[0], argv_exec, envp)
; parent returns with rax=child_pid (>=1) or <0 on error

global do_spawn
%include "macros.inc"
%include "syscalls_amd64.inc"

section .text
do_spawn:
    ; inputs:
    ;   rdi = argv_exec (pointer to argv[exec])
    ;   rsi = envp (pointer to envp array)
    ; outputs:
    ;   rax = child_pid (>=1) or negative errno

    push r12
    mov  r12, rdi         ; save argv_exec
    push r13
    mov  r13, rsi         ; save envp

    ; fork
    SYSCALL SYS_fork
    test rax, rax
    js   .ret             ; error
    jz   .in_child        ; rax==0 in child

    ; parent
    jmp .ret

.in_child:
    ; unblock signals in the child so it can receive TERM/INT/etc.
    sub rsp, 8
    mov qword [rsp], 0
    mov rdi, SIG_SETMASK
    mov rsi, rsp           ; empty mask -> unblock all
    xor rdx, rdx
    mov r10, 8
    SYSCALL SYS_rt_sigprocmask
    add rsp, 8

    ; become session leader
    SYSCALL SYS_setsid

    ; setpgid(0,0) -> pgid == pid
    xor rdi, rdi
    xor rsi, rsi
    SYSCALL SYS_setpgid

    ; execve(argv_exec[0], argv_exec, envp)
    mov rdi, [r12]        ; filename
    mov rsi, r12          ; argv
    mov rdx, r13          ; envp
    SYSCALL SYS_execve

    ; execve failed -> exit(127)
    mov rdi, 127
    SYSCALL SYS_exit

.ret:
    pop r13
    pop r12
    ret
