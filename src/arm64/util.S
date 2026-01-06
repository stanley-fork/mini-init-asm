.include "syscalls_aarch64.inc"
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

.global parse_u64_dec_checked
.type parse_u64_dec_checked, %function
// strict parse decimal u64 (digits only, non-empty, full-string)
// in:  x1 = ptr to NUL-terminated string
// out: x0 = value (undefined if x1=0), x1 = 1 if valid else 0
parse_u64_dec_checked:
    mov x0, #0
    mov x2, #10
    mov x5, #0              // ok=0
    ldrb w3, [x1]
    cbz w3, .bad
.p_loop_checked:
    ldrb w3, [x1]
    cbz w3, .ok
    cmp w3, #'0'
    blt .bad
    cmp w3, #'9'
    bgt .bad
    mov x5, #1
    umulh x4, x0, x2
    mul x0, x0, x2
    cbnz x4, .bad
    sub w3, w3, #'0'
    uxtw x3, w3
    adds x0, x0, x3
    bcs .bad
    add x1, x1, #1
    b .p_loop_checked
.ok:
    mov x1, x5
    ret
.bad:
    mov x1, #0
    ret

.global write_all
.type write_all, %function
// write_all(fd=x0, buf=x1, len=x2) -> x0=0 on success, negative errno on error
// Retries on EINTR; handles partial writes.
write_all:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!

    mov x19, x0        // fd
    mov x20, x1        // buf
    mov x21, x2        // remaining
    cbz x21, .write_all_ok

.write_all_loop:
    mov x0, x19
    mov x1, x20
    mov x2, x21
    SYSCALL SYS_write
    cmp x0, #0
    bgt .write_all_wrote
    beq .write_all_err0
    neg x4, x0
    cmp x4, #EINTR
    beq .write_all_loop
    b .out
.write_all_wrote:
    sub x21, x21, x0
    add x20, x20, x0
    cbnz x21, .write_all_loop
.write_all_ok:
    mov x0, #0
.out:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
.write_all_err0:
    mov x0, #-1
    b .out
