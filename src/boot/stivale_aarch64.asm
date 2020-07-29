.section .stivalehdr
.8byte stack_top // stack
.2byte 1 | 2 | 4 // flags
.2byte 0 // framebuffer_width
.2byte 0 // framebuffer_height
.2byte 0 // framebuffer_bpp
.8byte _start

.section .text
.global _start
_start:
.extern stivale_main
  BL stivale_main
1:
  WFI
  B 1b

.section .bss
stack_bottom:
.zero 1024 - 16
stack_top:
.zero 16
