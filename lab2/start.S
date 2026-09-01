.section .text
.global _start

_start:
    ldr x1, =0x5ff00000
    mov sp, x1

    mov x0, #0

    b .
