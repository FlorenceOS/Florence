section .stivalehdr
  dq stack_top
  dw 1 ; Graphics ploxx
  dw 0 ; Width
  dw 0 ; Height
  dw 0 ; bpp
  dq 0 ; Entry override

extern kernel_entry
extern kernel_args

section .text
extern stivale_entry
       stivale_entry:
extern stivale_main
  call stivale_main

  lea rax, [rel kernel_args]
	mov rdx, [rel kernel_entry]
	jmp rdx

section .bss
resb 0x1000 - 16
stack_top:
resb 16
