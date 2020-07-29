.intel_syntax noprefix

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
  mov rax, cr4
  bts eax, 9   // OSFXSR
  bts eax, 20  // SMEP
  bts eax, 21  // SMAP
  mov cr4, rax

.extern stivale_main
  call stivale_main
1:
  pause
  jmp 1b

.section .bss
stack_bottom:
.zero 1024 - 16
stack_top:
.zero 16
