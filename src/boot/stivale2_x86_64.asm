.intel_syntax noprefix

.section .stivale2hdr, "a"
.8byte _start
.8byte stack_top
.8byte 0
.8byte framebuffer

.section .rodata.stivale
.balign 8
framebuffer:
.8byte 0x3ecc1bc43d0f7971
.8byte smp
.2byte 0
.2byte 0
.2byte 0

.balign 8
smp:
.8byte 0x1ab015085f3273df
.8byte lv5paging
.8byte 1

.balign 8
lv5paging:
.8byte 0x932f477032007e8f
.8byte 0

.section .text
.global _start
_start:
  lea rsp, stack_top
  mov rbp, rsp
  
.extern stivale2_main
  jmp   stivale2_main

.section .bss
.balign 16
stack_bottom:
.zero 4096 * 16 - 16
stack_top:
.zero 16
