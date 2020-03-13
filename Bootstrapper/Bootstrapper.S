; .intel_syntax noprefix

section .BootstrapHeader
dd 0xb16d1cc5
dw 0x6969, 0x1337

extern BootstrapSectors
db     BootstrapSectors

%macro dataSelDx 0
  mov ds, dx
  mov ss, dx
  mov fs, dx
  mov es, dx
  mov gs, dx
%endmacro

; Goes from 16 bit real mode to 32 bit protected mode, clobbers edx
%macro go16to32 0
  %push ctx16to32

  ; Disable interrupts
  cli

  ; Enable protected mode
  mov edx, cr0
  or edx, 1
  mov cr0, edx

  ; Far jump to 32 bit protected mode
  jmp 0x18:%$nextmode
[bits 32]
%$nextmode:
  mov dx, 0x20
  dataSelDx
  %pop ctx16to32
%endmacro

; Goes from 32 bit protected mode to 16 bit real mode, clobbers edx
%macro go32to16 0
  %push ctx32to16
  ; Far jump to 16 bit protected mode
  jmp 0x08:%$nextmode
[bits 16]
%$nextmode:
  ; Disable protected mode
  mov edx, cr0
  and edx, ~1
  mov cr0, edx

  ; Far jump to real mode
  jmp 0x00:%$anothermode
%$anothermode:
  xor dx, dx
  dataSelDx
  ; Reenable interrupts
  sti

  %pop ctx32to16
%endmacro

%macro checkVESAError 1
  cmp ax, 0x004F
  mov ax, %0
  jne vesaError
%endmacro

section .BootstrapEntry
[bits 16]
global bootstrapStart
       bootstrapStart:
  mov byte[driveNumber], dl

  ; WOHOOO WE MADE IT

  ; We just entered here in 16 bit mode
  ; but can switch to 32 and then 64 at any time.

  ; The problem is that there are a few things we want to do first
  ; First of all, we need to get ourself a VESA video mode, that's
  ; only possible from real mode/16 bit. So what we'll do is to
  ; have 16 bit code getting the related data structures then
  ; we'll pick a mode in 32 bits, jumping back and forth for each mode,
  ; because at least then we can write the structure parsing code in C++
  ; instead of asm.

  go16to32

  ; Do the C++ global constructors
extern callGlobalConstructors
  call callGlobalConstructors

extern setupMemory
  call setupMemory
extern doEarlyPaging
  call doEarlyPaging
extern loadKernelLoader
  call loadKernelLoader

  ; Enable PAE
  mov eax, cr4
  or  eax, 1 << 5
  mov cr4, eax

  ; Enable long mode and NX
  mov ecx, 0xC0000080 ; EFER MSR
  rdmsr
  or  eax, 1 << 8  ; LM bit
  or  eax, 1 << 11 ; NX bit
  wrmsr

  ; Enable paging
  mov eax, cr0
  or  eax, 1 << 31
  mov cr0, eax

  ; Reload cr3
  ; mov eax, cr3
  ; mov cr3, eax

  ; We have to grab these pointers before the switch to 64 bits. Thanks ELF.
extern loaderStack
  lea ebx, [loaderStack]
extern kernelLoaderEntry
  lea ecx, [kernelLoaderEntry]

  jmp 0x28:mode64
mode64:
  [bits 64]
  ; Switch over to 64 bit segments
  mov dx, 0x30
  dataSelDx

  ; Set stack pointer
  mov rsp, qword[ebx]

  mov rbp, rsp

  ; Enable SSE
  mov rax, cr0
  and ax, 0xFFFB
  or ax, 0x2
  mov cr0, rax
  mov rax, cr4
  or ax, 3 << 9
  mov cr4, rax

  ; Tailcall kernel loader
  mov rcx, qword[ecx]
  jmp rcx

  ; Following functions will be called from 32 bits mode
  [bits 32]
global getMemoryMap
       getMemoryMap:
  go32to16

  mov edx, 0x534D4150
  mov ebx, [mem + 24]
  mov di, mem
  mov eax, 0xE820
  mov ecx, 24
  int 0x15
  jc pastEnd
  mov [mem + 24], ebx
  mov [mem + 28], cl

finish_memmap:
  go16to32
  ret

  [bits 16]
pastEnd:
  mov [mem + 28], word 0
  jmp finish_memmap

  [bits 32]
global readDisk
       readDisk:
  mov byte[dap],     0x10     ; Size
  mov byte[dap + 1], 0        ; Reserved
  mov word[dap + 2], 0x1      ; Number of sectors to read
  mov word[dap + 4], diskdata ; Destination offset
  mov word[dap + 6], 0        ; Destination segment

  go32to16
  clc
  mov si, dap
  mov dl, byte[driveNumber]
  mov ah, 0x42
  int 0x13
  jnc finish
  mov byte[diskReadCode], ah
finish:
  go16to32
  ret

extern dap
extern diskdata
extern driveNumber
extern mem
extern diskReadCode
