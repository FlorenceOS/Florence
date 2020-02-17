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

l:hlt
  jmp l

section .bss
resb 16 * 1024
stack:
