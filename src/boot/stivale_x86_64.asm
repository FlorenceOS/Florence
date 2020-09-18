.intel_syntax noprefix

.set stivale_flags_value, 1 // we disable kaslr for now as the linker is not emitting relocations.

.section .stivalehdr
.8byte stack_top // stack
.2byte stivale_flags_value
.2byte 0 // framebuffer_width
.2byte 0 // framebuffer_height
.2byte 0 // framebuffer_bpp
.8byte _start

.section .text
.global _start
_start:
  lea rsp, stack_top
  mov rax, cr4
  //bts eax, 9   // OSFXSR
  //bts eax, 20  // SMEP
  //bts eax, 21  // SMAP
  mov cr4, rax

.extern stivale_main
  call stivale_main
1:
  pause
  jmp 1b

.section .rodata
.global stivale_flags
stivale_flags:
.2byte stivale_flags_value

.section .bss
stack_bottom:
.zero 4096 - 16
stack_top:
.zero 16
