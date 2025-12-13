; Common macros & helpers for Linux x86-64 syscalls (NASM)

%macro SYSCALL 1
    mov rax, %1
    syscall
%endmacro

; rdi = fd, rsi = ptr, rdx = len
%macro WRITE 3
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    SYSCALL SYS_write
%endmacro

; Exit with code in rdi
%macro EXIT 1
    mov rdi, %1
    SYSCALL SYS_exit
%endmacro

; Conditional stderr logger (requires extern g_verbose in the using module)
; usage: LOG msg_ptr, msg_len
%macro LOG 2
    push rdi
    push rsi
    push rdx
    cmp qword [rel g_verbose], 0
    je %%done
    call get_timestamp_ptr
    mov rax, SYS_write
    mov rdx, 18
    mov rdi, 2
    mov rsi, rax
    syscall
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, %1
    mov rdx, %2
    syscall
%%done:
    pop rdx
    pop rsi
    pop rdi
%endmacro

; set bit for signal number in sigset (sig-1)
; in: rdi = &sigset (128 bytes), rsi = sig
set_sig_bit:
    push rax
    push rcx
    push rdx
    mov eax, esi
    sub eax, 1              ; zero-based
    mov ecx, eax
    and ecx, 63             ; bit index
    shr eax, 6              ; qword index
    mov rdx, 1
    mov cl, cl
    shl rdx, cl
    mov rcx, rax
    shl rcx, 3              ; *8
    or  [rdi + rcx], rdx
    pop rdx
    pop rcx
    pop rax
    ret

; parse decimal env var value (digits only)
; in:  rsi = ptr to string (digits), out: rax = value
parse_u64_dec:
    xor rax, rax
  .loop:
    mov bl, [rsi]
    cmp bl, 0
    je  .done
    cmp bl, '0'
    jb  .done
    cmp bl, '9'
    ja  .done
    imul rax, rax, 10
    movzx rbx, bl
    sub rbx, '0'
    add rax, rbx
    inc rsi
    jmp .loop
  .done:
    ret

; strict parse decimal u64 (digits only, non-empty, full-string)
; in:  rsi = ptr to NUL-terminated string
; out: rax = value (undefined if rdx=0), rdx = 1 if valid else 0
parse_u64_dec_checked:
    xor rax, rax
    xor r11, r11              ; ok=0
    mov r8b, [rsi]
    test r8b, r8b
    je .bad
.loop_checked:
    mov r8b, [rsi]
    test r8b, r8b
    je .ok
    cmp r8b, '0'
    jb .bad
    cmp r8b, '9'
    ja .bad
    mov r11, 1
    mov rcx, 10
    mul rcx                   ; rdx:rax = rax*10
    test rdx, rdx
    jne .bad
    movzx rcx, r8b
    sub rcx, '0'
    add rax, rcx
    jc .bad
    inc rsi
    jmp .loop_checked
.ok:
    mov rdx, r11
    ret
.bad:
    xor rdx, rdx
    ret
