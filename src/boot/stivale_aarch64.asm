.set stivale_flags_value, 1 // we disable kaslr for now as the linker is not emitting relocations.

.section .stivalehdr
.8byte stack_top // stack
.2byte stivale_flags_value // flags
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
.zero 4096 - 16
stack_top:
.zero 16

.section .rodata
stivale_flags_value:
.2byte stivale_flags_value
