.intel_syntax noprefix

.section .KernelLoaderHeader
.byte 0x09, 0xF9, 0x11, 0x02
.byte 0x9D, 0x74, 0xE3, 0x5B
.byte 0xD8, 0x41, 0x56, 0xC5
.byte 0x63, 0x56, 0x88, 0xC0

.extern KernelLoaderSize
.8byte  KernelLoaderSize

.global unknownField
        unknownField:
.8byte 0x0

.global physFreeHead1
        physFreeHead1:
.ascii "PhysFre1"

.global physFreeHead2
        physFreeHead2:
.ascii "PhysFre2"

.global physFreeHead3
        physFreeHead3:
.ascii "PhysFre3"

.global physFreeHead4
        physFreeHead4:
.ascii "PhysFre4"

.global physFreeHead5
        physFreeHead5:
.ascii "PhysFre5"

.global physBase
        physBase:
.ascii "PhysBase"

.global physMemRanges
        physMemRanges:
.ascii "HighRang"

.global displayWidth
        displayWidth:
.ascii "DispWide"

.global displayHeight
        displayHeight:
.ascii "DispHigh"

.global displayPitch
        displayPitch:
.ascii "DispPitc"

.global framebuffer
        framebuffer:
.ascii "FrameBuf"

.global driveNumber
        driveNumber:
.ascii "DriveNum"

.ascii "FLORKLOD"
.code64
.global _start
        _start:
.extern doConstructors
  call  doConstructors

.extern assertAssumptions
  call  assertAssumptions

.extern consumeHighPhysicalMemory
  call  consumeHighPhysicalMemory
  
.extern unmapLowMemory
  call  unmapLowMemory

1:hlt
  jmp 1b
