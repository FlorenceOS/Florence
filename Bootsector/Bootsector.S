.intel_syntax noprefix

.global loadAddress
.set    loadAddress, 0x7C00

.section .Bootloader
.code16
.global loaderStart
        loaderStart:
  # Enable a20
  in al, 0x92
  or al, 2
  out 0x92, al

  mov sp, 0x7000 # Make a small stack

  jmp 0x0000:loadSectors - loaderStart + loadAddress

.balign 8
GDT:
GDTNull:   .quad 0x000F00000000FFFF
GDT16Code: .quad 0x000F9A000000FFFF # Present, Code / Data, Executable, entire 20 bits address space
GDT16Data: .quad 0x000F92000000FFFF # Present, Code / Data, NE, Write,  entire 20 bits address space
GDT32Code: .quad 0x00CF9A000000FFFF # Present, Code / Data, Executable, entire 32 bits address space
GDT32Data: .quad 0x00CF92000000FFFF # Present, Code / Data, NE, Write,  entire 32 bits address space
GDT64Code: .quad 0x00A09A0000000000 # Present, Code / Data, Executable, 64 bits
GDT64Data: .quad 0x0000920000000000 # Present, Code / Data, NE, Write,  64 bits
GDTDesc:
.word . - GDT - 1
.long GDT

loadSectors:
  # Load sectors at 0x07e00 (es:bx)
  mov bx, 0x07e0
  mov es, bx
  xor bx, bx

  # Zero out segments
  mov ds, bx
  mov ss, bx
  mov fs, bx
  mov gs, bx

  mov [driveNum], dl # Save drive number

  clc

  mov dh, 0          # Head 0
  mov dl, [driveNum] # Drive
  mov cx, 0x0002     # Cylinder 0, sector 1
  mov ax, 0x0201     # Number of sectors to read (al) = 1
                     # Command                   (ah) = 2 (Read Sectors From Drive)

  # Read sectors
beforeFirstRead:
  int 0x13
afterFirstRead:
  jc loadError1

  xor bx, bx         # Load at 0x07e00

  # Check magic
  cmp dword ptr es:[bx], 0xb16d1cc5
  jne invalidMagic
  cmp word ptr es:[bx + 4], 0x6969
  jne invalidMagic
  cmp word ptr es:[bx + 6], 0x1337
  jne invalidMagic
  # What a cool image. Let's load it.

  mov dh, 0          # Head 0
  mov dl, [driveNum] # Drive
  mov cx, 0x0003     # Cylinder 0, sector 2+
  mov al, es:[bx+8]  # Get the number of sectors to load now (al)
  mov ah, 0x02       # Command (ah) = 2 (Read Sectors From Drive)

  # Load the rest at 0x8000
  mov bx, 0x0800
  mov es, bx
  xor bx, bx

  # Read sectors
beforeSecondRead:
  int 0x13
afterSecondRead:
  jc loadError2


jumpNextStage:
  # Load global descriptor table
  lgdt [GDTDesc]

  xor ax, ax
  mov es, ax

  # Tailcall the next stage in the bootloader
  jmp 0x8000

# All of the below functions have to be called before switching to
# protected mode, since they are only compatible with the starting
# real mode.
.code16
invalidMagic:
  mov si, offset invalidMagicStr
  call printStr
  jmp waitForKeyAndReboot

loadError1:
  mov si, offset firstErrStr
  jmp loadErrEnd
loadError2:
  mov si, offset secondErrStr
loadErrEnd:
  push 0
  pop es
  call printStr
printErrHex:
  # Output buffer
  mov si, offset printErrHexBuf

  # Put first character
  movzx bx, ah
  shr bx, 4
  add bx, offset hexstr
  mov bl, es:[bx]
  mov [si], bl

  # Put second character
  and ah, 0xf
  movzx bx, ah
  add bx, offset hexstr
  mov al, es:[bx]
  mov [si + 1], al

  # Print the string
  call printStr
waitForKeyAndReboot:
  mov si, pressKeyStr
  call printStr
  mov ah, 0
  int 0x16
reboot:
  jmp 0xf000:0xfff0

driveNum:
.byte 0x00

printErrHexBuf:
.byte 0x00
.byte 0x00
.byte 0x00

hexstr:
.ascii "0123456789ABCDEF"

printStr:
  lodsb
  or al, al   # if !al,
  jz printend # break
  mov ah, 0xE
  int 0x10    # al = char to print
  jmp printStr
printend:
  ret

invalidMagicStr:
  .asciz "[FMBR] Invalid magic! "
firstErrStr:
  .asciz "[FMBR] First sector: "
secondErrStr:
  .asciz "[FMBR] Other sectors: "
pressKeyStr:
  .asciz " press key to retry"
loaderEnd:
.global loaderSize
.set    loaderSize, loaderEnd - loaderStart

.section .DummyPartitionTable
.byte 0x80
.byte 0x01, 0x00, 0x00
.byte 0x01
.byte 0x01, 0x00, 0x00
.long 0x00000001
.long 0x00000001

.section .BootSignature
.byte 0x55
.byte 0xAA
