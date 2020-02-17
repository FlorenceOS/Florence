section .text.entry

[bits 64]

global _start
_start:
  ; Save pointer to kernel arguments
extern kernelArgumentPtr
  mov [rel kernelArgumentPtr], rax

  ; Set up a stack
  lea rax, [rel stackBottom]
  mov rsp, rax
  mov rbp, rsp

extern callGlobalConstructors
  call callGlobalConstructors

extern loadKernelArugments
  call loadKernelArugments

extern kernelMain
  call kernelMain

l:hlt
  jmp l

section .bss
stackTop:
resb 2048
stackBottom:
