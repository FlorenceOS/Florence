%macro dataSelDx 0
  mov ds, dx
  mov ss, dx
  mov fs, dx
  mov es, dx
  mov gs, dx
%endmacro

section .data
[bits 16]
global ap_boot_start
ap_boot_start: ; This will be loaded at address 0
  cli
  cld
l:
  jmp l
  jmp 0x0000:(cont - ap_boot_start)
cont:
  xor dx, dx
  dataSelDx
  mov sp, 0x2FF0 ; Stack starts at 0x2000
  lgdt [ap_boot_gdtr - ap_boot_start]

  mov edx, cr0
  or edx, 1
  mov cr0, edx

  jmp (GDT32Code - ap_boot_gdt):(bits32 - ap_boot_start)
  [bits 32]
bits32:
  mov dx, (GDT32Data - ap_boot_gdt)
  dataSelDx

  ; Set paging root
  mov eax, 0x1000
  mov cr3, eax

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

  jmp (GDT64Code - ap_boot_start):(bits64 - ap_boot_start)
  [bits 64]
bits64:
  mov dx, (GDT64Data - ap_boot_gdt)
  dataSelDx

  lgdt [rel ap_boot_new_gdtr]
  lidt [rel ap_boot_new_idtr]

  mov dx, [rel ap_boot_new_ds]
  dataSelDx

  jmp far [rel ap_boot_target]

ap_boot_gdt:
GDTNull:   dq 0x000F00000000FFFF
GDT32Code: dq 0x00CF9A000000FFFF ; Present, Code / Data, Executable, entire 32 bits address space
GDT32Data: dq 0x00CF92000000FFFF ; Present, Code / Data, NE, Write,  entire 32 bits address space
GDT64Code: dq 0x00A09A0000000000 ; Present, Code / Data, Executable, 64 bits
GDT64Data: dq 0x0000920000000000 ; Present, Code / Data, NE, Write,  64 bits
ap_boot_gdtr:
dw $ - ap_boot_gdt - 1
dd (ap_boot_gdt - ap_boot_start)
ap_boot_new_gdtr:
dw 0
dq 0
ap_boot_new_idtr:
dw 0
dq 0
ap_boot_target:
extern booted_ap
dq booted_ap
ap_boot_new_cs:
dw 0
ap_boot_new_ds:
dw 0
global ap_boot_end
ap_boot_end:

section .text
  [bits 64]
global ap_boot_store_current
ap_boot_store_current:
  sgdt [rel ap_boot_new_gdtr]
  sidt [rel ap_boot_new_idtr]
  mov ax, cs
  mov [rel ap_boot_new_cs], ax
  mov ax, ds
  mov [rel ap_boot_new_ds], ax
  ret

