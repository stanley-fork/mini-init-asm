.include "syscalls_aarch64.inc"
.include "macros_arm64.inc"

.bss
.align 6
sigset:        .skip 128
signalfd_buf:  .skip 128
token_buf:     .skip 16
signalfd_fd:   .skip 8
rtmin_val:     .skip 8
rtmax_val:     .skip 8
rt_enabled:    .skip 8

.text
.align 2
.global setup_signals_and_fd
.global read_signalfd_once
.global get_signalfd_fd
.extern g_verbose
.extern log_prefix_num
.extern get_timestamp_ptr
.extern set_sig_bit
.extern parse_u64_dec
.extern parse_u64_dec_checked

setup_signals_and_fd:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x19, x0               // envp
    mov x25, #0               // track if EP_SIGNALS was provided

    adrp x20, sigset
    add x20, x20, :lo12:sigset

    mov x21, #0
    mov x22, #0
.zero_loop:
    add x23, x20, x22
    stp x21, x21, [x23]
    add x22, x22, #16
    cmp x22, #128
    blt .zero_loop

    mov x0, x20
    mov x1, #SIGHUP
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGINT
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGQUIT
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGTERM
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGCHLD
    bl set_sig_bit

    // extra forwards
    mov x0, x20
    mov x1, #SIGUSR1
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGUSR2
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGPIPE
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGWINCH
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGTTIN
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGTTOU
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGCONT
    bl set_sig_bit
    mov x0, x20
    mov x1, #SIGALRM
    bl set_sig_bit

    // Parse optional EP_SIGRTMIN/EP_SIGRTMAX (required for RT* tokens)
    adrp x0, rt_enabled
    add x0, x0, :lo12:rt_enabled
    str xzr, [x0]
    adrp x0, rtmin_val
    add x0, x0, :lo12:rtmin_val
    str xzr, [x0]
    adrp x0, rtmax_val
    add x0, x0, :lo12:rtmax_val
    str xzr, [x0]

    mov x26, #0               // found rtmin
    mov x27, #0               // found rtmax
    mov x22, x19
.find_sigrt_env:
    ldr x23, [x22]
    cbz x23, .after_sigrt_env
    adrp x0, ep_sigrtmin_pref
    add x0, x0, :lo12:ep_sigrtmin_pref
    mov x1, x23
    bl prefix_match
    cbz x0, .chk_sigrtmax
    mov x1, x0
    bl parse_u64_dec_checked
    cbz x1, .next_sigrt_env
    adrp x2, rtmin_val
    add x2, x2, :lo12:rtmin_val
    str x0, [x2]
    mov x26, #1
    b .next_sigrt_env
.chk_sigrtmax:
    adrp x0, ep_sigrtmax_pref
    add x0, x0, :lo12:ep_sigrtmax_pref
    mov x1, x23
    bl prefix_match
    cbz x0, .next_sigrt_env
    mov x1, x0
    bl parse_u64_dec_checked
    cbz x1, .next_sigrt_env
    adrp x2, rtmax_val
    add x2, x2, :lo12:rtmax_val
    str x0, [x2]
    mov x27, #1
.next_sigrt_env:
    add x22, x22, #8
    b .find_sigrt_env
.after_sigrt_env:
    cmp x26, #1
    bne .sigrt_done
    cmp x27, #1
    bne .sigrt_done
    adrp x0, rtmin_val
    add x0, x0, :lo12:rtmin_val
    ldr x0, [x0]
    cmp x0, #1
    blt .sigrt_done
    cmp x0, #KERNEL_SIGMAX
    bgt .sigrt_done
    adrp x1, rtmax_val
    add x1, x1, :lo12:rtmax_val
    ldr x1, [x1]
    cmp x1, #1
    blt .sigrt_done
    cmp x1, #KERNEL_SIGMAX
    bgt .sigrt_done
    cmp x0, x1
    bge .sigrt_done
    adrp x2, rt_enabled
    add x2, x2, :lo12:rt_enabled
    mov x3, #1
    str x3, [x2]
.sigrt_done:

    // Parse EP_SIGNALS (CSV)
    mov x22, x19
.find_env:
    ldr x23, [x22]
    cbz x23, .after_env
    adrp x0, ep_sigpref
    add x0, x0, :lo12:ep_sigpref
    mov x1, x23
    bl prefix_match
    cbz x0, .next_env
    mov x25, #1
    mov x1, x0          // value pointer
.parse_csv:
    ldrb w2, [x1]
    cbz w2, .after_env
    cmp w2, #' '
    beq .skip_space
    mov x3, x1          // token start
.tok_scan:
    ldrb w2, [x1]
    cbz w2, .tok_done
    cmp w2, #','
    beq .tok_done
    add x1, x1, #1
    b .tok_scan
.tok_done:
    mov x24, x1         // token end (delimiter or NUL)
    // trim trailing spaces
    mov x10, x24
.trim_end:
    cmp x10, x3
    ble .trim_done
    ldrb w11, [x10, #-1]
    cmp w11, #' '
    bne .trim_done
    sub x10, x10, #1
    b .trim_end
.trim_done:
    sub x5, x10, x3      // length
    cmp x5, #0
    ble .after_token
    cmp x5, #15
    bgt .unknown_tok
    adrp x6, token_buf
    add x6, x6, :lo12:token_buf
    mov x7, x5
    mov x8, x3
.copy_loop:
    ldrb w9, [x8]
    strb w9, [x6]
    add x6, x6, #1
    add x8, x8, #1
    subs x7, x7, #1
    bne .copy_loop
    mov w9, #0
    strb w9, [x6]
    adrp x6, token_buf
    add x6, x6, :lo12:token_buf

    mov x0, x6
    adrp x1, tok_USR1
    add x1, x1, :lo12:tok_USR1
    bl token_eq
    cmp x0, #1
    beq .set_usr1

    mov x0, x6
    adrp x1, tok_USR2
    add x1, x1, :lo12:tok_USR2
    bl token_eq
    cmp x0, #1
    beq .set_usr2

    mov x0, x6
    adrp x1, tok_PIPE
    add x1, x1, :lo12:tok_PIPE
    bl token_eq
    cmp x0, #1
    beq .set_pipe

    mov x0, x6
    adrp x1, tok_WINCH
    add x1, x1, :lo12:tok_WINCH
    bl token_eq
    cmp x0, #1
    beq .set_winch

    mov x0, x6
    adrp x1, tok_TTIN
    add x1, x1, :lo12:tok_TTIN
    bl token_eq
    cmp x0, #1
    beq .set_ttin

    mov x0, x6
    adrp x1, tok_TTOU
    add x1, x1, :lo12:tok_TTOU
    bl token_eq
    cmp x0, #1
    beq .set_ttou

    mov x0, x6
    adrp x1, tok_CONT
    add x1, x1, :lo12:tok_CONT
    bl token_eq
    cmp x0, #1
    beq .set_cont

    mov x0, x6
    adrp x1, tok_ALRM
    add x1, x1, :lo12:tok_ALRM
    bl token_eq
    cmp x0, #1
    beq .set_alrm

    // Numeric signal token (decimal)
    ldrb w0, [x6]
    cmp w0, #'0'
    blt 1f
    cmp w0, #'9'
    bgt 1f
    mov x1, x6
    bl parse_u64_dec_checked
    cbz x1, .unknown_tok
    cmp x0, #1
    blt .unknown_tok
    cmp x0, #KERNEL_SIGMAX
    bgt .unknown_tok
    cmp x0, #SIGKILL
    beq .unknown_tok
    cmp x0, #SIGSTOP
    beq .unknown_tok
    mov x1, x0
    mov x0, x20
    bl set_sig_bit
    b .after_token

1:
    // Check if token starts with "RT" (real-time signal)
    ldrb w0, [x6]
    cmp w0, #'R'
    bne .unknown_tok
    ldrb w0, [x6, #1]
    cmp w0, #'T'
    bne .unknown_tok
    // Require explicit runtime SIGRTMIN/SIGRTMAX
    adrp x2, rt_enabled
    add x2, x2, :lo12:rt_enabled
    ldr x2, [x2]
    cbz x2, .rt_disabled
    // Parse number after "RT"
    add x1, x6, #2
    bl parse_u64_dec_checked
    cbz x1, .unknown_tok
    // Validate range: 1..(rtmax-rtmin) (rtmin+1..rtmax)
    cmp x0, #0
    beq .unknown_tok
    adrp x2, rtmax_val
    add x2, x2, :lo12:rtmax_val
    ldr x2, [x2]
    adrp x3, rtmin_val
    add x3, x3, :lo12:rtmin_val
    ldr x3, [x3]
    sub x2, x2, x3
    cmp x0, x2
    bgt .unknown_tok
    // Calculate rtmin + number
    adrp x2, rtmin_val
    add x2, x2, :lo12:rtmin_val
    ldr x2, [x2]
    add x1, x0, x2
    mov x0, x20
    bl set_sig_bit
    b .after_token

.rt_disabled:
    LOG log_rt_needs_env, log_rt_needs_env_len
    b .after_token

.unknown_tok:
    LOG log_unknown_token, log_unknown_token_len
    b .after_token

.set_usr1:
    mov x0, x20
    mov x1, #SIGUSR1
    bl set_sig_bit
    b .after_token
.set_usr2:
    mov x0, x20
    mov x1, #SIGUSR2
    bl set_sig_bit
    b .after_token
.set_pipe:
    mov x0, x20
    mov x1, #SIGPIPE
    bl set_sig_bit
    b .after_token
.set_winch:
    mov x0, x20
    mov x1, #SIGWINCH
    bl set_sig_bit
    b .after_token
.set_ttin:
    mov x0, x20
    mov x1, #SIGTTIN
    bl set_sig_bit
    b .after_token
.set_ttou:
    mov x0, x20
    mov x1, #SIGTTOU
    bl set_sig_bit
    b .after_token
.set_cont:
    mov x0, x20
    mov x1, #SIGCONT
    bl set_sig_bit
    b .after_token
.set_alrm:
    mov x0, x20
    mov x1, #SIGALRM
    bl set_sig_bit

.after_token:
    mov x1, x24
    ldrb w2, [x1]
    cbz w2, .after_env
    add x1, x1, #1
    b .parse_csv
.skip_space:
    add x1, x1, #1
    b .parse_csv
.next_env:
    add x22, x22, #8
    b .find_env

.after_env:
    cbz x25, .skip_epsig_log
    LOG log_epsig_done, log_epsig_done_len
.skip_epsig_log:

    // Block signals
    mov x0, #SIG_BLOCK
    mov x1, x20
    mov x2, #0
    mov x3, #8
    SYSCALL SYS_rt_sigprocmask

    // signalfd
    mov x0, #-1
    mov x1, x20
    mov x2, #8
    mov x3, #SFD_CLOEXEC
    mov x4, #SFD_NONBLOCK
    orr x3, x3, x4
    SYSCALL SYS_signalfd4
    cmp x0, #0
    blt .sfd_err

    mov x24, x0
    adrp x1, signalfd_fd
    add x1, x1, :lo12:signalfd_fd
    str x24, [x1]

    mov x2, x24
    adrp x0, log_sfd_prefix
    add x0, x0, :lo12:log_sfd_prefix
    mov x1, #log_sfd_prefix_len
    bl log_prefix_num
    mov x0, x24
    b .ret

.ret:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

.sfd_err:
    LOG log_sfd_err, log_sfd_err_len
    mov x0, #-1
    b .ret

read_signalfd_once:
    adrp x0, signalfd_fd
    add x0, x0, :lo12:signalfd_fd
    ldr x0, [x0]
    adrp x1, signalfd_buf
    add x1, x1, :lo12:signalfd_buf
    mov x2, #128
1:
    SYSCALL SYS_read
    cmp x0, #128
    beq 2f
    cmp x0, #0
    blt .read_err
    b .read_err
2:
    adrp x1, signalfd_buf
    add x1, x1, :lo12:signalfd_buf
    ldr w0, [x1]
    ret
.read_err:
    cmp x0, #-EINTR
    beq 1b
    mov x0, #-1
    ret

get_signalfd_fd:
    adrp x0, signalfd_fd
    add x0, x0, :lo12:signalfd_fd
    ldr x0, [x0]
    ret

// token_eq(temp, const)
// token_eq(temp, const)
token_eq:
    mov x2, x0
    mov x3, x1
.te_loop:
    ldrb w4, [x2]
    ldrb w5, [x3]
    cmp w4, w5
    bne .te_ne
    cbz w4, .te_eq
    add x2, x2, #1
    add x3, x3, #1
    b .te_loop
.te_eq:
    mov x0, #1
    ret
.te_ne:
    mov x0, #0
    ret

.text
.align 2
prefix_match:
    mov x2, x0
    mov x3, x1
.pm_loop:
    ldrb w4, [x2]
    cbz w4, .pm_no
    ldrb w5, [x3]
    cmp w4, w5
    bne .pm_no
    cmp w4, #'='
    beq .pm_value
    add x2, x2, #1
    add x3, x3, #1
    b .pm_loop
.pm_value:
    add x3, x3, #1
    mov x0, x3
    ret
.pm_no:
    mov x0, #0
    ret

.section .rodata
log_sfd_prefix:     .asciz "DEBUG: signalfd created fd="
.equ log_sfd_prefix_len, . - log_sfd_prefix - 1
log_sfd_err:        .asciz "ERROR: signalfd4 failed"
.equ log_sfd_err_len, . - log_sfd_err - 1
log_unknown_token:  .asciz "WARN: Unknown EP_SIGNALS token ignored"
.equ log_unknown_token_len, . - log_unknown_token - 1
log_rt_needs_env:  .asciz "WARN: RT* EP_SIGNALS tokens require EP_SIGRTMIN and EP_SIGRTMAX; ignoring RT token"
.equ log_rt_needs_env_len, . - log_rt_needs_env - 1
log_epsig_done:     .asciz "DEBUG: EP_SIGNALS parsed"
.equ log_epsig_done_len, . - log_epsig_done - 1

ep_sigpref: .asciz "EP_SIGNALS="
ep_sigrtmin_pref: .asciz "EP_SIGRTMIN="
ep_sigrtmax_pref: .asciz "EP_SIGRTMAX="
tok_USR1:   .asciz "USR1"
tok_USR2:   .asciz "USR2"
tok_PIPE:   .asciz "PIPE"
tok_WINCH:  .asciz "WINCH"
tok_TTIN:   .asciz "TTIN"
tok_TTOU:   .asciz "TTOU"
tok_CONT:   .asciz "CONT"
tok_ALRM:   .asciz "ALRM"
