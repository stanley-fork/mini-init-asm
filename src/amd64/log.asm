; Logging helpers with decimal numbers
;
; log_prefix_num(prefix_ptr, prefix_len, value)
;   rdi=prefix_ptr, rsi=prefix_len, rdx=value (u64)
; Writes: prefix, decimal(value), '\n' to stderr if g_verbose!=0
;
; write_all(fd, buf, len)
;   rdi=fd, rsi=buf, rdx=len
; Writes until all bytes are written or a non-EINTR error occurs.
; Returns rax=0 on success, or negative errno on error.
;
	global log_prefix_num
	global write_all
	extern g_verbose
	%include "syscalls_amd64.inc"

section .text
write_all:
    push rbx
    push r12
    mov r12, rdi        ; fd
    mov rbx, rdx        ; remaining
    test rbx, rbx
    jz .ok
.loop:
    mov rax, SYS_write
    mov rdi, r12
    syscall
    cmp rax, 0
    jg .wrote
    cmp rax, 0
    je .err             ; 0-byte write -> treat as error
    ; rax < 0
    mov rcx, rax
    neg rcx
    cmp rcx, EINTR
    je .loop
    jmp .out            ; return negative errno
.wrote:
    sub rbx, rax
    add rsi, rax
    mov rdx, rbx
    test rbx, rbx
    jnz .loop
.ok:
    xor rax, rax
.out:
    pop r12
    pop rbx
    ret
.err:
    mov rax, -1
    jmp .out

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
    mov rdi, 2
    mov rsi, r14
    mov rdx, r15
    call write_all
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
    mov rdi, 2
    mov rsi, r14
    mov rdx, r13
    call write_all
    ; write newline
    mov rdi, 2
    lea rsi, [rel ln_str]
    mov rdx, 1
    call write_all
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
