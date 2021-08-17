.intel_syntax noprefix

.global __bootstrap_stack_top

.section .stivale2hdr, "aw"
.8byte _start
.8byte __bootstrap_stack_top
.8byte 0
.8byte framebuffer

.section .rodata.stivale, "aw"
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
  lea rsp, [rip + __bootstrap_stack_top]

  push 0
  push 0

  mov rbp, rsp
  
.extern stivale2Main
  call  stivale2Main

.section .bss.stk, "a"
__bootstrap_stack_bottom:
.space 128 * 1024
__bootstrap_stack_top:
