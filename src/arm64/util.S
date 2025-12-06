.include "macros_arm64.inc"

.text
.align 2
.global set_sig_bit
.type set_sig_bit, %function
set_sig_bit:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!

    sub x1, x1, #1
    and x19, x1, #63
    lsr x20, x1, #6
    mov x21, #1
    lsl x21, x21, x19
    lsl x20, x20, #3
    add x22, x0, x20
    ldr x0, [x22]
    orr x0, x0, x21
    str x0, [x22]

    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

.global parse_u64_dec
.type parse_u64_dec, %function
parse_u64_dec:
    mov x0, #0
    mov x2, #10
.p_loop:
    ldrb w3, [x1]
    cbz w3, .done
    cmp w3, #'0'
    blt .done
    cmp w3, #'9'
    bgt .done
    mul x0, x0, x2
    sub w3, w3, #'0'
    add x0, x0, x3
    add x1, x1, #1
    b .p_loop
.done:
    ret
