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

.global physFreeHead
        physFreeHead:
.ascii "PhysFree"

.global physBase
        physBase:
.ascii "PhysBase"

.global physMemRanges
        physMemRanges:
.ascii "HighFree"

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
  
.extern unmapLowMemory
  call  unmapLowMemory

.extern consumeHighPhysicalMemory
  call  consumeHighPhysicalMemory

  jmp .
