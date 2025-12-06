; Logging helpers with decimal numbers
;
; log_prefix_num(prefix_ptr, prefix_len, value)
;   rdi=prefix_ptr, rsi=prefix_len, rdx=value (u64)
; Writes: prefix, decimal(value), '\n' to stderr if g_verbose!=0
;
global log_prefix_num
extern g_verbose
%include "syscalls_amd64.inc"

section .text
log_prefix_num:
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; check verbosity
    cmp qword [rel g_verbose], 0
    je .out
    ; save args
    mov r14, rdi          ; prefix_ptr
    mov r15, rsi          ; prefix_len
    mov rbx, rdx          ; value
    ; write prefix
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, r14
    mov rdx, r15
    syscall
    ; convert rbx to decimal into stack buffer
    sub rsp, 32
    lea r12, [rsp+32]     ; end
    xor r13, r13          ; length
    mov rax, rbx
    test rax, rax
    jne .conv_loop
    ; zero special-case
    mov byte [r12-1], '0'
    lea r14, [r12-1]
    mov r13, 1
    jmp .have_num
.conv_loop:
    xor rdx, rdx
    mov r8, 10
    div r8                ; rax=quot, rdx=rem
    add dl, '0'
    mov byte [r12-1], dl
    lea r12, [r12-1]
    inc r13
    test rax, rax
    jne .conv_loop
    mov r14, r12          ; start ptr
.have_num:
    ; write number
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, r14
    mov rdx, r13
    syscall
    ; write newline
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, [rel ln_str]
    mov rdx, 1
    syscall
    add rsp, 32
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
ln_str: db 10
