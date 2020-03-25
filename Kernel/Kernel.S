section .text.entry

[bits 64]
global _start
_start:
  ; Save pointer to kernel arguments
extern kernelArgumentPtr
  mov [rel kernelArgumentPtr], rax

  ; Switch to new GDT
  lgdt [rel GDTDesc]

  ; Set code segment
  lea rax, [rel jmpdest]
  jmp far [rax]

f:
  ; Set data segments
  mov ax, GDT64Data - GDT
  mov es, ax
  mov ss, ax
  mov ds, ax
  mov fs, ax
  mov gs, ax

  ; Set up a stack
  lea rax, [rel stack]
  mov rsp, rax
  mov rbp, rsp

extern callGlobalConstructors
  call callGlobalConstructors

extern initializeVmm
  call initializeVmm

extern kernelMain
  call kernelMain

  ; Exit task
  int $31 ; This is hex but there is no way to make that clear :(

section .rodata
jmpdest:
dq f
dw GDT64Code - GDT

GDT:
GDTNull:   dq 0x000F00000000FFFF
GDT64Code: dq 0x00A09A0000000000 ; Present, Code / Data, Executable, 64 bits
GDT64Data: dq 0x0000920000000000 ; Present, Code / Data, NE, Write,  64 bits
GDTDesc:
dw $ - GDT - 1
dq GDT

section .bss
; To terminate stack unwinding, stacks need to have 16 bytes at the end
resb 16 * 1024
stack:
resb 16
