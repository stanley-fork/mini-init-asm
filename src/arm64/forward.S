.include "syscalls_aarch64.inc"
.include "macros_arm64.inc"

.text
.align 2
.global forward_signal_to_group

forward_signal_to_group:
    neg x0, x0        // pid = -pgid
    SYSCALL SYS_kill
    ret
