.intel_syntax noprefix

.section .BootstrapHeader
.long 0xb16d1cc5
.word 0x6969, 0x1337

.byte   BootstrapSectors
.global desiredWidth
        desiredWidth: .word 1440
.global desiredHeight
        desiredHeight: .word 900

.section .BootstrapEntry
.code16

.macro dataSelDx
  mov ds, dx
  mov ss, dx
  mov fs, dx
  mov es, dx
  mov gs, dx
.endm

# Goes from 16 bit real mode to 32 bit protected mode, clobbers edx
.macro go16to32
  # Enable protected mode
  mov edx, cr0
  or edx, 1
  mov cr0, edx

  # Far jump to 32 bit protected mode
  jmp 0x18:1f
.code32
1:mov dx, 0x20
  dataSelDx
.endm

# Goes from 32 bit protected mode to 16 bit real mode, clobbers edx
.macro go32to16
  # Far jump to 16 bit protected mode
  jmp 0x08:1f
.code16
1:
  # Disable protected mode
  mov edx, cr0
  and edx, ~1
  mov cr0, edx

  # Far jump to real mode
  jmp 0x00:2f

2:xor dx, dx
  dataSelDx
.endm

.macro checkVESAError str
  cmp ax, 0x004F
  mov ax, offset \str
  jne vesaError
.endm

.global bootstrapStart
        bootstrapStart:
  mov byte ptr[diskNum], dl

  # WOHOOO WE MADE IT

  # We just entered here in 16 bit mode
  # but can switch to 32 and then 64 at any time.

  # The problem is that there are a few things we want to do first
  # First of all, we need to get ourself a VESA video mode, that's
  # only possible from real mode/16 bit. So what we'll do is to
  # have 16 bit code getting the related data structures then
  # we'll pick a mode in 32 bits, jumping back and forth for each mode,
  # because at least then we can write the structure parsing code in C++
  # instead of asm.

  go16to32

  call  doConstructors
  call  initializeDebug

  go32to16

  # First let's get a list of video modes.
  mov ax, 0x4F00
  mov di, offset biosBuf
  int 0x10
  checkVESAError getVideoModeListError

  go16to32

  call setupVideo

  # Clear ebx for memory map
  mov dword ptr[biosBuf + 24], 0

  call setupMemory
  call doEarlyPaging
  call loadKernelLoader
  call doDestructors

  # Enable PAE
  mov eax, cr4
  or  eax, 1 << 5
  mov cr4, eax

  # Enable long mode and NX
  mov ecx, 0xC0000080 # EFER MSR
  rdmsr
  or  eax, 1 << 8  # LM bit
  or  eax, 1 << 11 # NX bit
  wrmsr

  # Reload cr3
  mov eax, cr3
  mov cr3, eax

  # Enable paging
  mov eax, cr0
  or  eax, 1 << 31
  mov cr0, eax

  # We have to grab these pointers before the switch to 64 bits. Thanks ELF.
  lea ebx, [loaderStack]
  lea ecx, [kernelLoaderEntry]

  jmp 0x28:1f
1:.code64
  # Switch over to 64 bit segments
  mov dx, 0x30
  dataSelDx

  # Set stack pointer
  mov rsp, qword ptr[ebx]

  # Enable SSE
  mov rax, cr0
  and ax, 0xFFFB
  or ax, 0x2
  mov cr0, rax
  mov rax, cr4
  or ax, 3 << 9
  mov cr4, rax

  # Tailcall kernel loader
  mov rcx, qword ptr[ecx]
  jmp rcx

getVideoModeListError:
  .asciz "Could not get video mode list!"
getVideoModeError:
  .asciz "Could not get video mode!"
setVideoModeError:
  .asciz "Could not set video mode!"

  # setupVideo will call these from 32 bits!
.code32
.global getVideoMode
        getVideoMode:
  go32to16

  mov ax, 0x4F01
  mov di, offset currentModeBuf
  int 0x10
afterGetMode:
  checkVESAError getVideoModeError

  go16to32
  ret

.global setVideoMode
        setVideoMode:
  go32to16

  and bx, (1 << 14) - 1 # Use bits 0-13
  or  bx,  1 << 14      # Linear framebuffer

  mov ax, 0x4F02
  int 0x10
  checkVESAError setVideoModeError

  go16to32
  ret

.global getMemoryMap
        getMemoryMap:
  go32to16

  mov edx, 0x534D4150
  mov ebx, [biosBuf + 24]
  mov di, offset biosBuf
  mov eax, 0xE820
  mov ecx, 24
  int 0x15
  mov [biosBuf + 24], ebx
  mov [biosBuf + 28], cl

  go16to32
  ret

.global readDisk
        readDisk:
  mov byte ptr[currentModeBuf],     0x10           # Size
  mov byte ptr[currentModeBuf + 1], 0              # Reserved
  mov word ptr[currentModeBuf + 2], 0x1            # Number of sectors to read
  mov word ptr[currentModeBuf + 4], offset biosBuf # Destination offset
  mov word ptr[currentModeBuf + 6], 0              # Destination segment

  go32to16
  lea si, currentModeBuf
  mov dl, byte ptr[diskNum]
  mov ah, 0x42
  int 0x13

  go16to32
  ret

.global diskNum
        diskNum:
  .byte 0
diskReadCode:
  .byte 0
.balign 8

.code16
vesaError:
  go16to32
  jmp printVideoModeError

.balign 8
.global biosBuf
        biosBuf:
  .ascii "VBE2"
  .space 512 - (.-biosBuf)

.section .bss
.global currentModeBuf
        currentModeBuf:
  .space 256
