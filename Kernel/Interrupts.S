[bits 64]

extern isrHandler

section .rodata
global exceptionHandlers
exceptionHandlers:

%macro makeHandlerPtr 1
dq handler%1
%endmacro

%assign i 0
%rep 32
makeHandlerPtr i
%assign i i+1
%endrep

section .text
%macro noHandler 1
handler%1 :
  iretq
%endmacro

%macro exceptionHandlerWiCode 1
handler%1 :
  push %1
  jmp exceptionCommon
%endmacro

%macro exceptionHandlerNoCode 1
handler%1 :
  push 0
  push %1
  jmp exceptionCommon
%endmacro

extern exceptionHandler

exceptionCommon:
  push rax
  push rbx
  push rcx
  push rdx
  push rbp
  push rsi
  push rdi
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  call exceptionHandler
  pop  r15
  pop  r14
  pop  r13
  pop  r12
  pop  r11
  pop  r10
  pop  r9
  pop  r8
  pop  rdi
  pop  rsi
  pop  rbp
  pop  rdx
  pop  rcx
  pop  rbx
  pop  rax
  add  rsp, 16 ; Pop error code and interrupt number
  iretq

exceptionHandlerNoCode 0  ; Divide by zero
exceptionHandlerNoCode 1  ; Debug
exceptionHandlerNoCode 2  ; NMI
exceptionHandlerNoCode 3  ; Breakpoint
exceptionHandlerNoCode 4  ; Overflow
exceptionHandlerNoCode 5  ; Bound range exceeded
exceptionHandlerNoCode 6  ; Invalid opcode
exceptionHandlerNoCode 7  ; Device not available
exceptionHandlerWiCode 8  ; Double fault
noHandler              9
exceptionHandlerWiCode 10 ; Invalid TSS
exceptionHandlerWiCode 11 ; Segment not present
exceptionHandlerWiCode 12 ; Stack-Segmentation fault
exceptionHandlerWiCode 13 ; General protection fault
exceptionHandlerWiCode 14 ; Page fault
noHandler              15
exceptionHandlerNoCode 16 ; x87 Floating-Point exception
exceptionHandlerWiCode 17 ; Alignment check
exceptionHandlerNoCode 18 ; Machine check
exceptionHandlerNoCode 19 ; SIMD Floating-Point. exception
exceptionHandlerNoCode 20 ; Virtualization exception
noHandler              21
noHandler              22
noHandler              23
noHandler              24
noHandler              25
noHandler              26
noHandler              27
noHandler              28
noHandler              29
exceptionHandlerWiCode 30 ; Security exception
noHandler              31
