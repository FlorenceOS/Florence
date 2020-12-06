.intel_syntax noprefix

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
  xor rbp, rbp
  
.extern stivale2_main
  jmp   stivale2_main

.section .bss
stack_bottom:
.zero 1024 * 16 - 16
stack_top:
.zero 16
