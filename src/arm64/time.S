.include "syscalls_aarch64.inc"
.include "macros_arm64.inc"

.bss
.align 4
time_buffer:
    .skip 19

.text
.align 2
.global get_timestamp_ptr
.extern g_verbose
.extern g_arm64_fallback

get_timestamp_ptr:
    // In EP_ARM64_FALLBACK mode, avoid udiv-heavy timestamp formatting (QEMU-user workaround).
    adrp x0, g_arm64_fallback
    add x0, x0, :lo12:g_arm64_fallback
    ldr x0, [x0]
    cbnz x0, .blank

    adrp x0, g_verbose
    add x0, x0, :lo12:g_verbose
    ldr x0, [x0]
    cbz x0, .empty

    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!

    sub sp, sp, #16
    mov x8, SYS_clock_gettime
    mov x0, CLOCK_REALTIME
    mov x1, sp
    svc #0
    ldr x19, [sp]        // seconds
    ldr x20, [sp, #8]    // nanoseconds
    add sp, sp, #16

    // microseconds = nanoseconds / 1000
    mov x0, x20
    mov x1, #1000
    udiv x21, x0, x1

    adrp x22, time_buffer
    add x22, x22, :lo12:time_buffer

    // fill buffer with ASCII '0'
    mov x23, #0
    mov x24, #'0'
.fill_loop:
    cmp x23, #19
    bge .digits
    strb w24, [x22, x23]
    add x23, x23, #1
    b .fill_loop

.digits:
    // seconds -> 10 digits
    mov x0, x19
    mov x1, #10
    add x3, x22, #9
    mov x4, #10
.sec_loop:
    udiv x5, x0, x1
    mul x6, x5, x1
    sub x6, x0, x6
    add x6, x6, #'0'
    strb w6, [x3]
    sub x3, x3, #1
    mov x0, x5
    subs x4, x4, #1
    bne .sec_loop

    // dot
    mov w6, #'.'
    strb w6, [x22, #10]

    // microseconds -> 6 digits
    mov x0, x21
    mov x1, #10
    add x3, x22, #16
    mov x4, #6
.micro_loop:
    udiv x5, x0, x1
    mul x6, x5, x1
    sub x6, x0, x6
    add x6, x6, #'0'
    strb w6, [x3]
    sub x3, x3, #1
    mov x0, x5
    subs x4, x4, #1
    bne .micro_loop

    // trailing space and NUL
    mov w6, #' '
    strb w6, [x22, #17]
    mov w6, #0
    strb w6, [x22, #18]

    mov x0, x22

    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

.empty:
    adrp x0, time_buffer
    add x0, x0, :lo12:time_buffer
    mov w1, #0
    strb w1, [x0]
    ret

.blank:
    adrp x0, time_buffer
    add x0, x0, :lo12:time_buffer
    mov x1, #0
    mov w2, #' '
.blank_loop:
    cmp x1, #18
    bge .blank_done
    strb w2, [x0, x1]
    add x1, x1, #1
    b .blank_loop
.blank_done:
    ret
