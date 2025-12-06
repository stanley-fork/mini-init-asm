; _start: parse argv/env, spawn child in its own PGID, forward signals to group,
; reap children, graceful shutdown with escalation using timerfd + epoll.

global _start
global g_verbose
global g_exit_code_base
extern do_spawn
extern forward_signal_to_group
extern reap_children_nonblock
extern extract_exit_code
extern setup_signals_and_fd
extern read_signalfd_once
extern get_wait_status_ptr
extern get_signalfd_fd
extern epoll_create_fd
extern epoll_add_fd
extern epoll_wait_once
extern create_grace_timerfd
extern read_timerfd_tick
extern get_timestamp_ptr
extern log_prefix_num

%include "macros.inc"
%include "syscalls_amd64.inc"

section .rodata
usage_msg: db "usage: mini-init-amd64 [--verbose|-v] [--version|-V] -- <cmd> [args...]", 10, 0
version_msg: db "mini-init-amd64 0.1.1", 10, 0
log_first_soft: db "DEBUG: first soft signal received", 10
log_first_soft_len: equ $ - log_first_soft
log_escalate_kill: db "DEBUG: escalating to SIGKILL", 10
log_escalate_kill_len: equ $ - log_escalate_kill
log_sigchld_ok:  db "DEBUG: SIGCHLD handled", 10
log_sigchld_ok_len: equ $ - log_sigchld_ok
log_restart:     db "DEBUG: restarting child", 10
log_restart_len: equ $ - log_restart
log_max_restarts: db "DEBUG: max restarts reached, exiting", 10
log_max_restarts_len: equ $ - log_max_restarts
log_backoff_wait: db "DEBUG: waiting for backoff before restart", 10
log_backoff_wait_len: equ $ - log_backoff_wait
log_debug_restart_enabled: db "DEBUG: restart_enabled=", 0
log_debug_restart_enabled_len: equ $ - log_debug_restart_enabled - 1
log_debug_wait_status: db "DEBUG: wait_status=", 0
log_debug_wait_status_len: equ $ - log_debug_wait_status - 1
log_debug_shutdown: db "DEBUG: shutdown=", 0
log_debug_shutdown_len: equ $ - log_debug_shutdown - 1
log_debug_env_check: db "DEBUG: checking env: ", 0
log_debug_env_check_len: equ $ - log_debug_env_check - 1
log_debug_value: db "DEBUG: value=", 0
log_debug_value_len: equ $ - log_debug_value - 1
log_newline: db 10

section .bss
align 8
g_verbose:          resq 1
g_child_pid:        resq 1
g_child_exited:     resq 1
g_child_status:     resq 1
g_grace_secs:       resq 1
g_shutdown:         resq 1
g_killed:           resq 1
g_epfd:             resq 1
g_sfd:              resq 1
g_tfd:              resq 1
g_argv_exec:        resq 1
g_envp:             resq 1
g_exit_code_base:   resq 1
g_restart_enabled:  resq 1
g_max_restarts:     resq 1
g_restart_count:    resq 1
g_restart_backoff:  resq 1
g_backoff_tfd:      resq 1

section .text

; tiny strcmp (nul-terminated); rdi=a, rsi=b; returns 1 if equal
str_eq:
    push rax
  .loop:
    mov al, [rdi]
    cmp al, [rsi]
    jne .ne
    test al, al
    je .eq
    inc rdi
    inc rsi
    jmp .loop
  .eq:
    pop rax
    mov rax, 1
    ret
  .ne:
    pop rax
    xor rax, rax
    ret

; simple prefix match: rdi = "NAME=", rsi = envstr; returns rax=ptr to value or 0
prefix_match:
    push rbx
    mov rbx, rsi
    mov rsi, rdi
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

_start:
    ; stack: [argc][argv...][0][envp...][0]
    mov rbx, rsp
    mov rax, [rbx]         ; argc
    mov r12, rax
    lea r13, [rbx + 8]     ; argv
    ; find envp
    mov rcx, r12
    lea r14, [r13 + rcx*8 + 8]   ; points to the NULL after argv => envp

    ; defaults
    mov qword [g_verbose], 0
    mov qword [g_grace_secs], 10
    mov qword [g_exit_code_base], 128
    mov qword [g_restart_enabled], 0
    mov qword [g_max_restarts], 0
    mov qword [g_restart_count], 0
    mov qword [g_restart_backoff], 1
    mov qword [g_backoff_tfd], 0

    ; parse argv: look for -v/--verbose and -- delimiter
    mov r11, 1             ; i = 1 (use r11 to avoid clobbering by calls)
    mov r15, 0             ; exec index found? 0=no
.parse_argv:
    cmp r11, r12
    jge .argv_done
    mov rax, [r13 + r11*8] ; argv[i]
    mov rbx, rax
    ; check "--"
    lea rsi, [rel delim_str]
    mov rdi, rbx
    call str_eq
    cmp rax, 1
    je .found_delim
    ; check "-v"/"--verbose"
    lea rsi, [rel v1_str]
    mov rdi, rbx
    call str_eq
    cmp rax, 1
    je .set_v
    lea rsi, [rel v2_str]
    mov rdi, rbx
    call str_eq
    cmp rax, 1
    je .set_v
    ; check "-V"/"--version"
    lea rsi, [rel ver1_str]
    mov rdi, rbx
    call str_eq
    cmp rax, 1
    je .show_version
    lea rsi, [rel ver2_str]
    mov rdi, rbx
    call str_eq
    cmp rax, 1
    je .show_version
    jmp .next_i
.show_version:
    mov rdi, 1
    mov rsi, version_msg
    mov rdx, 21
    WRITE 1, rsi, rdx
    EXIT 0
.set_v:
    mov qword [g_verbose], 1
    jmp .next_i
.found_delim:
    ; argv_exec = &argv[i+1]
    lea rax, [r13 + (r11+1)*8]
    mov [g_argv_exec], rax
    jmp .argv_done
.next_i:
    inc r11
    jmp .parse_argv
.argv_done:
    cmp qword [g_argv_exec], 0
    jne .have_cmd
    ; print usage and exit 2
    mov rdi, 2
    mov rsi, usage_msg
    mov rdx, 60
    WRITE 2, rsi, rdx
    EXIT 2

.have_cmd:
    ; envp pointer
    mov [g_envp], r14

    ; Parse EP_GRACE_SECONDS (optional)
    mov rbx, r14
.find_env:
    mov rax, [rbx]
    test rax, rax
    je .env_done
    ; compare prefix EP_GRACE_SECONDS=
    lea rdi, [rel ep_pref]
    mov rsi, rax
    call prefix_match
    test rax, rax
    jz .next_env
    ; rax points to value string
    mov rsi, rax
    call parse_u64_dec
    mov [g_grace_secs], rax
    jmp .env_done
.next_env:
    add rbx, 8
    jmp .find_env
.env_done:
    ; Check EP_SUBREAPER and set PR_SET_CHILD_SUBREAPER if enabled
    mov rbx, r14
.find_subreaper:
    mov rax, [rbx]
    test rax, rax
    je .subreaper_done
    lea rdi, [rel ep_subreaper_pref]
    mov rsi, rax
    call prefix_match
    test rax, rax
    jz .next_subreaper_env
    ; Check if value is "1"
    mov al, [rax]
    cmp al, '1'
    jne .subreaper_done
    mov al, [rax+1]
    test al, al
    jnz .subreaper_done
    ; Set PR_SET_CHILD_SUBREAPER
    mov rdi, PR_SET_CHILD_SUBREAPER
    mov rsi, 1
    xor rdx, rdx
    xor r10, r10
    xor r8, r8
    SYSCALL SYS_prctl
    jmp .subreaper_done
.next_subreaper_env:
    add rbx, 8
    jmp .find_subreaper
.subreaper_done:
    ; Parse EP_EXIT_CODE_BASE (optional)
    mov rbx, r14
.find_exit_base:
    mov rax, [rbx]
    test rax, rax
    je .exit_base_done
    lea rdi, [rel ep_exit_base_pref]
    mov rsi, rax
    call prefix_match
    test rax, rax
    jz .next_exit_base_env
    ; rax points to value string
    mov rsi, rax
    call parse_u64_dec
    mov [g_exit_code_base], rax
    jmp .exit_base_done
.next_exit_base_env:
    add rbx, 8
    jmp .find_exit_base
.exit_base_done:
    ; Parse EP_RESTART_ENABLED (optional)
    mov rbx, r14
.find_restart_enabled:
    mov rax, [rbx]
    test rax, rax
    je .restart_enabled_done
    lea rdi, [rel ep_restart_enabled_pref]
    mov rsi, rax
    call prefix_match
    test rax, rax
    jz .next_restart_enabled_env
    ; Debug: log when we find a match
    cmp qword [g_verbose], 1
    jne .skip_match_debug
    push rax
    push rbx
    push rcx
    push rdi
    push rsi
    push rdx
    mov rdi, 2
    lea rsi, [rel log_debug_env_check]
    mov rdx, log_debug_env_check_len
    SYSCALL SYS_write
    mov rdi, 2
    mov rsi, [rbx]  ; The env var string
    xor rdx, rdx
  .len_env:
    cmp byte [rsi+rdx], 0
    je  .len_env_done
    inc rdx
    cmp rdx, 64
    jb  .len_env
  .len_env_done:
    SYSCALL SYS_write
    mov rdi, 2
    lea rsi, [rel log_newline]
    mov rdx, 1
    SYSCALL SYS_write
    pop rdx
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    pop rax
.skip_match_debug:
    ; Check if value is "1"
    ; Save value pointer in rcx before we corrupt rax (rcx is not used in this section)
    mov rcx, rax
    ; Debug: log the value
    cmp qword [g_verbose], 1
    jne .skip_value_debug
    push rax
    push rbx
    push rcx
    push rdi
    push rsi
    push rdx
    mov rsi, rcx          ; value pointer
    call parse_u64_dec    ; parse value to number
    mov rdx, rax
    lea rdi, [rel log_debug_value]
    mov rsi, log_debug_value_len
    call log_prefix_num
    pop rdx
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    pop rax
.skip_value_debug:
    mov al, [rcx]
    cmp al, '1'
    jne .next_restart_enabled_env  ; Not "1", continue searching
    mov al, [rcx+1]
    test al, al
    jnz .next_restart_enabled_env  ; Not null-terminated after "1", continue searching
    ; Found EP_RESTART_ENABLED=1, enable restart
    mov qword [g_restart_enabled], 1
    LOG log_restart, log_restart_len  ; Debug: log that we found it
    jmp .restart_enabled_done
.next_restart_enabled_env:
    add rbx, 8
    jmp .find_restart_enabled
.restart_enabled_done:
    ; Parse EP_MAX_RESTARTS (optional)
    mov rbx, r14
.find_max_restarts:
    mov rax, [rbx]
    test rax, rax
    je .max_restarts_done
    lea rdi, [rel ep_max_restarts_pref]
    mov rsi, rax
    call prefix_match
    test rax, rax
    jz .next_max_restarts_env
    ; rax points to value string
    mov rsi, rax
    call parse_u64_dec
    mov [g_max_restarts], rax
    jmp .max_restarts_done
.next_max_restarts_env:
    add rbx, 8
    jmp .find_max_restarts
.max_restarts_done:
    ; Parse EP_RESTART_BACKOFF_SECONDS (optional)
    mov rbx, r14
.find_restart_backoff:
    mov rax, [rbx]
    test rax, rax
    je .restart_backoff_done
    lea rdi, [rel ep_restart_backoff_pref]
    mov rsi, rax
    call prefix_match
    test rax, rax
    jz .next_restart_backoff_env
    ; rax points to value string
    mov rsi, rax
    call parse_u64_dec
    mov [g_restart_backoff], rax
    jmp .restart_backoff_done
.next_restart_backoff_env:
    add rbx, 8
    jmp .find_restart_backoff
.restart_backoff_done:

    ; Setup signals + signalfd (pass envp for EP_SIGNALS)
    mov rdi, [g_envp]
    call setup_signals_and_fd
    ; signalfd fd
    call get_signalfd_fd
    mov [g_sfd], rax

    ; Create epoll and add signalfd
    call epoll_create_fd
    mov [g_epfd], rax
    mov rdi, rax
    mov rsi, [g_sfd]
    call epoll_add_fd

    ; Spawn child
    mov rbx, [g_argv_exec]
    mov rsi, [g_envp]
    mov rdi, rbx
    call do_spawn
    mov [g_child_pid], rax

.main_loop:
    ; Wait for either a signal event (sfd) or the grace timer (tfd)
    mov rdi, [g_epfd]
    call epoll_wait_once
    cmp rax, -1
    je .main_loop
    mov rbx, rax           ; ready fd
    ; signalfd ready?
    mov rax, [g_sfd]
    cmp rbx, rax
    jne .check_timer
    ; read signo
    call read_signalfd_once
    mov rdx, rax           ; signo
    cmp rdx, SIGCHLD
    je  .handle_chld
    ; if not a "soft shutdown" signal, just forward and continue
    cmp rdx, SIGTERM
    je  .soft_signal
    cmp rdx, SIGINT
    je  .soft_signal
    cmp rdx, SIGHUP
    je  .soft_signal
    cmp rdx, SIGQUIT
    je  .soft_signal
    ; forward other signals (USR1,USR2,WINCH,CONT,ALRM,TTIN,TTOU,PIPE) without arming timer
    mov rdi, [g_child_pid]
    mov rsi, rdx
    call forward_signal_to_group
    jmp .main_loop
.soft_signal:
    ; forward received soft signal to group
    mov rdi, [g_child_pid]
    mov rsi, rdx
    call forward_signal_to_group
    ; opportunistic reap: child may have exited immediately after soft signal
    call reap_children_nonblock
    cmp rax, 0
    jle .after_opportunistic
    mov rdx, [g_child_pid]
    cmp rax, rdx
    jne .after_opportunistic
    ; compute exit code and exit
    call get_wait_status_ptr
    mov rdi, [rax]
    call extract_exit_code
    mov [g_child_status], rax
    mov qword [g_child_exited], 1
    LOG log_sigchld_ok, log_sigchld_ok_len
    mov rax, [g_child_status]
    EXIT rax
.after_opportunistic:
    ; start shutdown on first soft signal
    cmp qword [g_shutdown], 1
    je .main_loop
    LOG log_first_soft, log_first_soft_len
    ; create timerfd for grace window
    mov rdi, [g_grace_secs]
    call create_grace_timerfd
    mov [g_tfd], rax
    ; add to epoll
    mov rdi, [g_epfd]
    mov rsi, [g_tfd]
    call epoll_add_fd
    mov qword [g_shutdown], 1
    jmp .main_loop

.check_timer:
    ; Check if this is the backoff timer
    mov rax, [g_backoff_tfd]
    test rax, rax
    jz .check_grace_timer
    cmp rbx, rax
    jne .check_grace_timer
    ; Backoff timer expired -> restart child
    mov rdi, rax
    call read_timerfd_tick
    ; Close backoff timerfd
    mov rdi, [g_backoff_tfd]
    SYSCALL SYS_close
    mov qword [g_backoff_tfd], 0
    ; Reset state for restart
    mov qword [g_child_exited], 0
    mov qword [g_shutdown], 0
    mov qword [g_killed], 0
    ; Spawn new child
    mov rbx, [g_argv_exec]
    mov rsi, [g_envp]
    mov rdi, rbx
    call do_spawn
    mov [g_child_pid], rax
    ; Increment restart count
    mov rax, [g_restart_count]
    inc rax
    mov [g_restart_count], rax
    LOG log_restart, log_restart_len
    jmp .main_loop
.check_grace_timer:
    ; timerfd event -> escalate SIGKILL if child not yet exited
    mov rax, [g_tfd]
    test rax, rax
    jz .main_loop
    cmp rbx, rax
    jne .main_loop
    ; drain timerfd
    mov rdi, [g_tfd]
    call read_timerfd_tick
    ; if child not exited yet -> kill -KILL
    cmp qword [g_child_exited], 1
    je .main_loop
    LOG log_escalate_kill, log_escalate_kill_len
    mov rdi, [g_child_pid]
    mov rsi, SIGKILL
    call forward_signal_to_group
    mov qword [g_killed], 1
    jmp .main_loop

.handle_chld:
    ; reap all
    call reap_children_nonblock
    cmp rax, 0
    je .main_loop
    ; is it our main child?
    mov rdx, [g_child_pid]
    cmp rax, rdx
    jne .main_loop
    ; Get wait status and save it on stack
    call get_wait_status_ptr
    mov rdi, [rax]
    push rdi              ; Save wait status on stack
    ; compute exit code
    call extract_exit_code
    mov [g_child_status], rax
    mov qword [g_child_exited], 1
    
    ; Debug: log restart_enabled, shutdown, and wait_status
    mov rdx, [g_restart_enabled]
    lea rdi, [rel log_debug_restart_enabled]
    mov rsi, log_debug_restart_enabled_len
    call log_prefix_num
    mov rdx, [g_shutdown]
    lea rdi, [rel log_debug_shutdown]
    mov rsi, log_debug_shutdown_len
    call log_prefix_num
    pop rax               ; Get wait status for debug
    push rax              ; Put it back
    mov rdx, rax
    lea rdi, [rel log_debug_wait_status]
    mov rsi, log_debug_wait_status_len
    call log_prefix_num
    
    ; Check if we should restart (only if restart enabled, not in shutdown, and child was killed by signal)
    cmp qword [g_restart_enabled], 1
    jne .no_restart_pop
    cmp qword [g_shutdown], 1
    je .no_restart_pop
    ; Check if child was killed by signal (not normal exit) - use saved wait status
    pop rax               ; Restore wait status from stack
    push rax              ; Save it again for potential reuse
    and rax, 0x7f
    cmp rax, 0
    je .no_restart_pop  ; Normal exit, don't restart
    ; Check max restarts
    mov rax, [g_max_restarts]
    test rax, rax
    jz .check_restart_count  ; 0 means unlimited
    mov rbx, [g_restart_count]
    cmp rbx, rax
    jge .max_restarts_reached
.check_restart_count:
    ; Check if we need backoff
    mov rax, [g_restart_backoff]
    test rax, rax
    jz .restart_immediately
    ; Create backoff timerfd
    mov rdi, rax
    call create_grace_timerfd
    mov [g_backoff_tfd], rax
    test rax, rax
    js .restart_immediately  ; If timerfd creation failed, restart immediately
    ; Add backoff timerfd to epoll
    mov rdi, [g_epfd]
    mov rsi, [g_backoff_tfd]
    call epoll_add_fd
    pop rax               ; Clean up stack (wait status) before backoff wait
    LOG log_backoff_wait, log_backoff_wait_len
    jmp .main_loop
.restart_immediately:
    pop rax               ; Clean up stack (wait status)
    ; Reset state for restart
    mov qword [g_child_exited], 0
    mov qword [g_shutdown], 0
    mov qword [g_killed], 0
    ; Spawn new child
    mov rbx, [g_argv_exec]
    mov rsi, [g_envp]
    mov rdi, rbx
    call do_spawn
    mov [g_child_pid], rax
    ; Increment restart count
    mov rax, [g_restart_count]
    inc rax
    mov [g_restart_count], rax
    LOG log_restart, log_restart_len
    jmp .main_loop
.max_restarts_reached:
    pop rax               ; Clean up stack
    LOG log_max_restarts, log_max_restarts_len
.no_restart_pop:
    pop rax               ; Clean up stack (wait status)
.no_restart:
    ; if we escalated to SIGKILL, force exit code (base+9)
    cmp qword [g_killed], 1
    jne .no_force_kill_rc
    mov rax, [g_exit_code_base]
    add rax, 9
    mov [g_child_status], rax
.no_force_kill_rc:
    LOG log_sigchld_ok, log_sigchld_ok_len
    mov rax, [g_child_status]
    EXIT rax

delim_str: db "--",0
v1_str:    db "-v",0
v2_str:    db "--verbose",0
ver1_str:  db "-V",0
ver2_str:  db "--version",0
ep_pref:   db "EP_GRACE_SECONDS=",0
ep_subreaper_pref: db "EP_SUBREAPER=",0
ep_exit_base_pref: db "EP_EXIT_CODE_BASE=",0
ep_restart_enabled_pref: db "EP_RESTART_ENABLED=",0
ep_max_restarts_pref: db "EP_MAX_RESTARTS=",0
ep_restart_backoff_pref: db "EP_RESTART_BACKOFF_SECONDS=",0
