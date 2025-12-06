global get_timestamp_ptr
extern g_verbose
%include "syscalls_amd64.inc"

%define CLOCK_REALTIME 0

section .bss
time_buffer: resb 19 ; "SSSSSSSSSS.mmmmmm "

section .text
get_timestamp_ptr:
    cmp qword [rel g_verbose], 0
    je .skip
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 16
    mov rax, SYS_clock_gettime
    mov rdi, CLOCK_REALTIME
    mov rsi, rsp
    syscall
    mov rbx, [rsp]        ; seconds
    mov r12, [rsp+8]      ; nanoseconds
    add rsp, 16
    ; convert ns to microseconds
    mov rax, r12
    xor rdx, rdx
    mov r13, 1000
    div r13               ; rax = microseconds
    mov r12, rax
    ; fill buffer with zeros
    lea r14, [rel time_buffer]
    mov rcx, 19/8 + 1
    xor rax, rax
.clr_loop:
    mov [r14+rcx*8-8], rax
    loop .clr_loop
    ; seconds -> 10 digits
    mov rcx, 10
    lea rsi, [r14+9]
    mov rax, rbx
.sec_loop:
    xor rdx, rdx
    mov r13, 10
    div r13
    add dl, '0'
    mov byte [rsi], dl
    dec rsi
    dec rcx
    jnz .sec_loop
    ; dot
    mov byte [r14+10], '.'
    ; microseconds -> 6 digits
    mov rcx, 6
    lea rsi, [r14+16]
    mov rax, r12
.micro_loop:
    xor rdx, rdx
    mov r13, 10
    div r13
    add dl, '0'
    mov byte [rsi], dl
    dec rsi
    dec rcx
    jnz .micro_loop
    ; trailing space and null
    mov byte [r14+17], ' '
    mov byte [r14+18], 0
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.skip:
    lea rax, [rel time_buffer]
    mov byte [rax], 0
    ret
