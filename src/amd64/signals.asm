; Block a set of signals and create signalfd for them
; Supports EP_SIGNALS=CSV to add extra names (USR1,USR2,PIPE,WINCH).

global setup_signals_and_fd
global read_signalfd_once
global get_wait_status_ptr
global get_signalfd_fd

%include "macros.inc"
%include "syscalls_amd64.inc"
extern g_verbose
extern get_timestamp_ptr
extern log_prefix_num
extern get_timestamp_ptr

section .bss
align 8
sigset:         resb 128           ; kernel_sigset_t (x86-64: 64 signals)
signalfd_buf:   resb 128           ; struct signalfd_siginfo
token_buf:      resb 16            ; temp buffer for EP_SIGNALS tokens
signalfd_fd:    resq 1

section .text

; Returns rax = fd (>=0) or <0 on error
; rdi = envp
setup_signals_and_fd:
    push r12
    mov r12, rdi

    ; Build mask: HUP, INT, QUIT, TERM, CHLD
    lea rdi, [rel sigset]
    ; zero 128 bytes
    mov rcx, 16
    xor rax, rax
  .zero:
    mov [rdi + rcx*8 - 8], rax
    loop .zero

    ; set default bits
    mov rsi, SIGHUP     ; 1
    call set_sig_bit
    mov rsi, SIGINT     ; 2
    call set_sig_bit
    mov rsi, SIGQUIT    ; 3
    call set_sig_bit
    mov rsi, SIGTERM    ; 15
    call set_sig_bit
    mov rsi, SIGCHLD    ; 17
    call set_sig_bit

    ; Add common forwards by default for robustness
    mov rsi, SIGUSR1
    call set_sig_bit
    mov rsi, SIGUSR2
    call set_sig_bit
    mov rsi, SIGPIPE
    call set_sig_bit
    mov rsi, SIGWINCH
    call set_sig_bit
    mov rsi, SIGTTIN
    call set_sig_bit
    mov rsi, SIGTTOU
    call set_sig_bit
    mov rsi, SIGCONT
    call set_sig_bit
    mov rsi, SIGALRM
    call set_sig_bit

    ; Parse EP_SIGNALS=CSV (optional)
    mov rbx, r12
    xor r14, r14          ; track if EP_SIGNALS parsed
  .find_env:
    mov rax, [rbx]
    test rax, rax
    je  .after_env
    ; check prefix "EP_SIGNALS="
    lea rdi, [rel ep_sigpref]
    mov rsi, rax
    call prefix_match
    test rax, rax
    jz  .next_env
    mov rsi, rax         ; pointer to value string
    mov r14, 1
    LOG log_epsig_found, log_epsig_found_len
  .parse_csv:
    mov al, [rsi]
    cmp al, 0
    je  .after_env
    cmp al, ' '
    je  .skip_space
    mov r8, rsi          ; token start
  .scan_token:
    mov al, [rsi]
    cmp al, 0
    je  .token_ready
    cmp al, ','
    je  .token_ready
    inc rsi
    jmp .scan_token
  .token_ready:
    mov r9, rsi          ; token end (points to delimiter or NUL)
    mov rcx, r9
    sub rcx, r8          ; token length
    ; trim trailing spaces
  .trim_end:
    cmp rcx, 0
    jle .after_token
    mov al, [r8 + rcx - 1]
    cmp al, ' '
    jne .trim_done
    dec rcx
    jmp .trim_end
  .trim_done:
    cmp rcx, 0
    jle .after_token
    cmp rcx, 15          ; max token size (buffer 16 incl NUL)
    ja .unknown_tok
    lea rdi, [rel token_buf]
    mov rsi, r8
    mov rdx, rcx         ; keep length in rdx
    mov rax, rcx
    mov rcx, rax
    rep movsb
    mov byte [rdi], 0    ; rdi now at end -> write NUL
    mov rsi, r9          ; restore current pointer
    lea rbx, [rel token_buf]
    lea rdx, [rel tok_USR1]
    call token_eq
    mov rsi, r9
    cmp rax, 1
    jne .chk_usr2
    mov rsi, SIGUSR1
    lea rdi, [rel sigset]
    call set_sig_bit
    jmp .after_token
  .chk_usr2:
    lea rdx, [rel tok_USR2]
    call token_eq
    mov rsi, r9
    cmp rax, 1
    jne .chk_pipe
    mov rsi, SIGUSR2
    lea rdi, [rel sigset]
    call set_sig_bit
    jmp .after_token
  .chk_pipe:
    lea rdx, [rel tok_PIPE]
    call token_eq
    mov rsi, r9
    cmp rax, 1
    jne .chk_winch
    mov rsi, SIGPIPE
    lea rdi, [rel sigset]
    call set_sig_bit
    jmp .after_token
  .chk_winch:
    lea rdx, [rel tok_WINCH]
    call token_eq
    mov rsi, r9
    cmp rax, 1
    jne .chk_ttin
    mov rsi, SIGWINCH
    lea rdi, [rel sigset]
    call set_sig_bit
    jmp .after_token
  .chk_ttin:
    lea rdx, [rel tok_TTIN]
    call token_eq
    mov rsi, r9
    cmp rax, 1
    jne .chk_ttou
    mov rsi, SIGTTIN
    lea rdi, [rel sigset]
    call set_sig_bit
    jmp .after_token
  .chk_ttou:
    lea rdx, [rel tok_TTOU]
    call token_eq
    mov rsi, r9
    cmp rax, 1
    jne .chk_cont
    mov rsi, SIGTTOU
    lea rdi, [rel sigset]
    call set_sig_bit
    jmp .after_token
  .chk_cont:
    lea rdx, [rel tok_CONT]
    call token_eq
    mov rsi, r9
    cmp rax, 1
    jne .chk_alarm
    mov rsi, SIGCONT
    lea rdi, [rel sigset]
    call set_sig_bit
    jmp .after_token
  .chk_alarm:
    lea rdx, [rel tok_ALRM]
    call token_eq
    mov rsi, r9
    cmp rax, 1
    jne .chk_rt
    mov rsi, SIGALRM
    lea rdi, [rel sigset]
    call set_sig_bit
    jmp .after_token
  .chk_rt:
    ; Check if token starts with "RT" (real-time signal)
    lea rbx, [rel token_buf]
    mov al, [rbx]
    cmp al, 'R'
    jne .unknown_tok
    mov al, [rbx+1]
    cmp al, 'T'
    jne .unknown_tok
    ; Parse number after "RT"
    lea rsi, [rbx+2]
    call parse_u64_dec_checked
    test rdx, rdx
    jz .unknown_tok
    ; Validate range: 1..(SIGRTMAX-SIGRTMIN) (SIGRTMIN+1..SIGRTMAX)
    cmp rax, 0
    je .unknown_tok
    cmp rax, (SIGRTMAX - SIGRTMIN)
    ja .unknown_tok
    ; Calculate SIGRTMIN + number
    add rax, SIGRTMIN
    mov rsi, rax
    lea rdi, [rel sigset]
    call set_sig_bit
    jmp .after_token
  .unknown_tok:
    LOG log_unknown_token, log_unknown_token_len
  .after_token:
    mov rsi, r9
    cmp byte [rsi], 0
    je .after_env
    inc rsi             ; skip comma
    jmp .parse_csv
  .skip_space:
    inc rsi
    jmp .parse_csv

  .next_env:
    add rbx, 8
    jmp .find_env
  .after_env:
    cmp r14, 0
    je .after_env_no_log
    LOG log_epsig_done, log_epsig_done_len
.after_env_no_log:

    ; Block them: rt_sigprocmask(SIG_BLOCK, &sigset, NULL, sizeof(k_sigset_t))
    mov rdi, SIG_BLOCK
    lea rsi, [rel sigset]
    xor rdx, rdx
    mov r10, 8          ; sizeof(kernel sigset mask in bytes on x86-64
    SYSCALL SYS_rt_sigprocmask

    ; signalfd4(-1, &sigset, 128, flags)
    mov rdi, -1
    lea rsi, [rel sigset]
    mov rdx, 8
    mov r10, SFD_CLOEXEC | SFD_NONBLOCK
    SYSCALL SYS_signalfd4
    test rax, rax
    js .sfd_err
    mov [rel signalfd_fd], rax
    ; log signalfd fd number
    mov rdx, rax
    lea rdi, [rel log_sfd_prefix]
    mov rsi, log_sfd_prefix_len
    call log_prefix_num
.ret:
    pop r12
    ret
.sfd_err:
    LOG log_sfd_create_err, log_sfd_create_err_len
    jmp .ret

; small helpers --------------------------------------------------------------

; prefix_match: rdi = PATTERN "NAME=", rsi = envstr
; returns rax = ptr to value (after '=') or 0
prefix_match:
    push rbx
    mov rbx, rsi       ; env string
    mov rsi, rdi       ; pattern
    mov rdi, rbx
  .p_loop:
    mov al, [rsi]
    cmp al, 0
    je .no
    cmp al, [rdi]
    jne .no
    cmp al, '='
    je .value
    inc rsi
    inc rdi
    jmp .p_loop
  .value:
    inc rdi
    mov rax, rdi
    pop rbx
    ret
  .no:
    xor rax, rax
    pop rbx
    ret

; token_eq: compare zero-terminated token rbx with expected rdx
; returns rax=1 if equal, else 0
token_eq:
    push rbx
    push rcx
    push rdx
    mov rsi, rbx
    mov rdi, rdx
  .l1:
    mov al, [rsi]
    cmp al, [rdi]
    jne .ne
    cmp al, 0
    je .eq
    inc rsi
    inc rdi
    jmp .l1
  .eq:
    mov rax, 1
    jmp .out
  .ne:
    xor rax, rax
  .out:
    pop rdx
    pop rcx
    pop rbx
    ret

; return signalfd fd
get_signalfd_fd:
    mov rax, [rel signalfd_fd]
    ret

; Read one signalfd_siginfo event (after readiness)
; returns in rax = signo (int) or <0 on error
read_signalfd_once:
    mov rdi, [rel signalfd_fd]
    lea rsi, [rel signalfd_buf]
    mov rdx, 128
    SYSCALL SYS_read
    test rax, rax
    js .err
    ; struct signalfd_siginfo starts with uint32_t ssi_signo
    mov eax, dword [rel signalfd_buf]
    movsx rax, eax
    ret
.err:
    ret

; From wait.asm
get_wait_status_ptr:
    extern wait_status
    lea rax, [rel wait_status]
    ret

section .text
; token_eq_range: compare token [rbx..rsi) to zero-terminated expected at rdx
; returns rax=1 if equal, else 0
token_eq_range:
    push rbx
    push rcx
    push rdx
    mov r8, rbx         ; start
    mov r9, rsi         ; end
    mov r10, rdx        ; expected
.ter_loop:
    cmp r8, r9
    jge .ter_after
    mov al, [r8]
    cmp al, [r10]
    jne .ter_no
    inc r8
    inc r10
    jmp .ter_loop
.ter_after:
    cmp byte [r10], 0
    jne .ter_no
    mov rax, 1
    jmp .ter_out
.ter_no:
    xor rax, rax
.ter_out:
    pop rdx
    pop rcx
    pop rbx
    ret
ep_sigpref: db "EP_SIGNALS=",0
tok_USR1:   db "USR1",0
tok_USR2:   db "USR2",0
tok_PIPE:   db "PIPE",0
tok_WINCH:  db "WINCH",0
tok_TTIN:   db "TTIN",0
tok_TTOU:   db "TTOU",0
tok_CONT:   db "CONT",0
tok_ALRM:   db "ALRM",0

section .rodata
log_unknown_token: db "WARN: Unknown EP_SIGNALS token ignored", 10
log_unknown_token_len: equ $ - log_unknown_token
log_sfd_prefix:  db "DEBUG: signalfd created fd=", 0
log_sfd_prefix_len: equ $ - log_sfd_prefix - 1
log_epsig_found: db "DEBUG: parsing EP_SIGNALS", 10
log_epsig_found_len: equ $ - log_epsig_found
log_epsig_done: db "DEBUG: EP_SIGNALS parsed", 10
log_epsig_done_len: equ $ - log_epsig_done
log_tok_check: db "DEBUG: EP_SIGNALS token check", 10
log_tok_check_len: equ $ - log_tok_check
log_sfd_create_err: db "ERROR: signalfd4 failed", 10
log_sfd_create_err_len: equ $ - log_sfd_create_err
