.set stivale_flags_value, 1 // we disable kaslr for now as the linker is not emitting relocations.

.section .stivale2hdr
.8byte _start
.8byte stack_top
.8byte 0
.8byte framebuffer

.section .rodata.stivale
framebuffer:
.8byte 0x3ecc1bc43d0f7971
.8byte smp
.2byte 0
.2byte 0
.2byte 0

smp:
.8byte 0x1ab015085f3273df
.8byte 0
.8byte 1

.section .text
.global _start
_start:
.extern stivale2_main
  B     stivale2_main

.section .bss
stack_bottom:
.zero 4096 - 16
stack_top:
.zero 16

.section .rodata
stivale_flags_value:
.2byte stivale_flags_value
