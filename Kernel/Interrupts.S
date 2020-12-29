; IRQs are allocated in the following manner:
; 0   - 31  (0x00 - 0x1F) CPU exceptions
; 32  - 47  (0x20 - 0x2F) IRQs
; 48  - 63  (0x30 - 0x3F) Sheduler calls

[bits 64]

%macro makeHandlerPtr 1
dq handler%1
%endmacro

section .data
global exceptionHandlers
exceptionHandlers: ; Interrupt 
%assign i 0
%rep 49
makeHandlerPtr i
%assign i i+1
%endrep

global irqHandlers
irqHandlers: ; Standard IRQs
%assign i 32
%rep 16
makeHandlerPtr i
%assign i i+1
%endrep

global schedulerCalls
schedulerCalls:
makeHandlerPtr 48
makeHandlerPtr 49

section .text
%macro noHandler 1
handler%1 :
  iretq
%endmacro

%macro exceptionHandlerWiCode 1
handler%1 :
  push %1
  jmp interruptCommon
%endmacro

%macro exceptionHandlerNoCode 1
handler%1 :
  push 0
  push %1
  jmp interruptCommon
%endmacro

%macro irqHandler 1
handler%1 :
  push 0
  push %1
  jmp interruptCommon
%endmacro

extern interruptHandler
interruptCommon:
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
  call interruptHandler
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
irqHandler             32 ; IRQ 0
irqHandler             33 ; IRQ 1
irqHandler             34 ; IRQ 2
irqHandler             35 ; IRQ 3
irqHandler             36 ; IRQ 4
irqHandler             37 ; IRQ 5
irqHandler             38 ; IRQ 6
irqHandler             39 ; IRQ 7
irqHandler             40 ; IRQ 8
irqHandler             41 ; IRQ 9
irqHandler             42 ; IRQ a
irqHandler             43 ; IRQ b
irqHandler             44 ; IRQ c
irqHandler             45 ; IRQ d
irqHandler             46 ; IRQ e
irqHandler             47 ; IRQ f
irqHandler             48 ; Task yield
irqHandler             49 ; Task exit
