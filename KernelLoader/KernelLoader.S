; .intel_syntax noprefix

section .KernelLoaderHeader
db 0x09, 0xF9, 0x11, 0x02
db 0x9D, 0x74, 0xE3, 0x5B
db 0xD8, 0x41, 0x56, 0xC5
db 0x63, 0x56, 0x88, 0xC0

extern KernelLoaderPages
dq     KernelLoaderPages

global unknownField
       unknownField:
dq 0x0

global physFree
       physFree:
db "PhysFree"

global physBase
       physBase:
db "PhysBase"

global physEnd
       physEnd:
db "PhysEnd", 0

global physMemRanges
       physMemRanges:
db "HighRang"

global vgaX
       vgaX:
db "DispVGAX"

global vgaY
       vgaY:
db "DispVGAY"

db "FLORKLOD"

global _start
       _start:
extern callGlobalConstructors
  call callGlobalConstructors

  mov byte [0xB8000], '?'
  hlt

extern kernelArguments
  lea rax, [kernelArguments]

extern kernelEntry
  mov rbx, [kernelEntry]
  jmp rbx

section .kernel
global bundledKernel
       bundledKernel:
  incbin "./build/Kernel/Kernel.elf"
global bundledKernelEnd
       bundledKernelEnd:
