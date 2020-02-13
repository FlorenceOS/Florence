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

global physFreeHead1
       physFreeHead1:
db "PhysFre1"

global physFreeHead2
       physFreeHead2:
db "PhysFre2"

global physFreeHead3
       physFreeHead3:
db "PhysFre3"

global physFreeHead4
       physFreeHead4:
db "PhysFre4"

global physFreeHead5
       physFreeHead5:
db "PhysFre5"

global physBase
       physBase:
db "PhysBase"

global physMemRanges
       physMemRanges:
db "HighRang"

global displayWidth
       displayWidth:
db "DispWide"

global displayHeight
       displayHeight:
db "DispHigh"

global displayPitch
       displayPitch:
db "DispPitc"

global framebuffer
       framebuffer:
db "FrameBuf"

global driveNumber
       driveNumber:
db "DriveNum"

db "FLORKLOD"

global _start
       _start:
  ; Enable SSE
  mov rax, cr0
  and ax, 0xFFFB
  or ax, 0x2
  mov cr0, rax
  mov rax, cr4
  or ax, 3 << 9
  mov cr4, rax

extern callGlobalConstructors
  call callGlobalConstructors
extern assertAssumptions
  call assertAssumptions
extern consumeHighPhysicalMemory
  call consumeHighPhysicalMemory
extern unmapLowMemory
  call unmapLowMemory

1:hlt
  jmp 1b
