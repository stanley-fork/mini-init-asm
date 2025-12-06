; forward signal to the child's process group using kill(-pgid, sig)

global forward_signal_to_group
%include "macros.inc"
%include "syscalls_amd64.inc"

section .text
; in: rdi = child_pgid, rsi = signo
forward_signal_to_group:
    ; kill(-pgid, sig)
    mov rax, rdi
    neg rax
    mov rdi, rax
    mov rdx, rsi    ; save sig in rdx
    mov rsi, rdx
    SYSCALL SYS_kill
    ret
