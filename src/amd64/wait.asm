; Non-blocking reap + status decode helpers

global reap_children_nonblock
global extract_exit_code
global wait_status
extern g_exit_code_base

%include "macros.inc"
%include "syscalls_amd64.inc"

section .bss
align 8
wait_status:    resq 1

section .text
; Loop wait4(-1, &status, WNOHANG, NULL) until no child.
; In:  rdi = main_child_pid
; Out: rax = main_child_pid if reaped, else 0
; Side-effect: if main child was reaped, stores its status in [wait_status]
reap_children_nonblock:
    push rbx
    push r12
    push r13
    mov r12, rdi        ; main pid
    xor rbx, rbx        ; found pid (0/ pid)
    xor r13, r13        ; saved main status
  .again:
    mov rdi, -1
    lea rsi, [rel wait_status]
    mov edx, 1          ; WNOHANG
    xor r10, r10
    SYSCALL SYS_wait4
    test rax, rax
    jg   .got           ; pid reaped
    cmp rax, 0
    je   .done          ; no child ready
    ; rax < 0 -> error
    cmp rax, -EINTR
    je  .again
    jmp  .done
  .got:
    cmp rax, r12
    jne .again
    mov rbx, rax
    mov r13, [rel wait_status]
    jmp .again
  .done:
    test rbx, rbx
    jz .out
    mov [rel wait_status], r13
  .out:
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

; Given a wait status in rdi, compute exit code to return:
; if signaled -> 128 + signo ; else -> exitstatus
extract_exit_code:
    ; If WIFSIGNALED: (status & 0x7f) != 0
    mov rax, rdi
    and rax, 0x7f
    cmp rax, 0
    jne .signaled
    ; exited -> (status >> 8) & 0xff
    mov rax, rdi
    shr rax, 8
    and rax, 0xff
    ret
  .signaled:
    ; g_exit_code_base + (status & 0x7f)
    mov rax, rdi
    and rax, 0x7f
    add rax, [rel g_exit_code_base]
    ret
