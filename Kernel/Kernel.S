section .text.entry

[bits 64]

global _start
_start:
  ; Save pointer to kernel arguments
extern kernelArgumentPtr
  mov [rel kernelArgumentPtr], rax

  ; Set up a stack
  lea rax, [rel stack]
  mov rsp, rax
  mov rbp, rsp

extern callGlobalConstructors
  call callGlobalConstructors

extern kernelMain
  call kernelMain

; To let the return address from kernelMain point to 
; _start, for the sake of stack traces, we have a nop here
  nop

l:hlt
  jmp l

section .bss
; To terminate stack unwinding, stacks need to have 16 bytes at the end
resb 16 * 1024
stack:
resb 16
resb 16 * 1024
interruptStack:
resb 16
resb 16 * 1024
pageFaultStack:
resb 16
resb 16 * 1024
doubleFaultStack:
resb 16
