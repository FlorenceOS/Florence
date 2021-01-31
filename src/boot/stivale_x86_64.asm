.intel_syntax noprefix

.set stivale_flags_value, 0x3 // we disable kaslr for now as the linker is not emitting relocations.

.section .stivalehdr, "a"
.8byte stack_top // stack
.2byte stivale_flags_value
.2byte 0 // framebuffer_width
.2byte 0 // framebuffer_height
.2byte 0 // framebuffer_bpp
.8byte _start

.section .text
.global _start
_start:
  xor rbp, rbp

.extern stivale_main
  jmp   stivale_main

.section .rodata
.global stivale_flags
stivale_flags:
.2byte stivale_flags_value

.section .bss
.balign 16
stack_bottom:
.zero 4096 * 16 - 16
stack_top:
.zero 16
