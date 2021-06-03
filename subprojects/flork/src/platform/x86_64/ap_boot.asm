.global ap_boot_begin
.global ap_boot_end

.section .data
.bits 16
.org 0x8000
ap_boot_begin:
  lgdt [ap_boot_temp_gdtr]
  mov eax, [ap_boot_cr3]
  mov cr3, eax

  mov eax, cr4
  or al, (1 << 5)
  mov cr4, eax

  mov ecx, 0xc0000080
  or ax, (1 << 8)
  wrmsr

  mov eax, 0x80000011
  mov cr0, eax
  jmp 0x08:(ap_boot_64)

.bits 64
ap_boot_64:
  lgdt [ap_boot_gdtr]
  lidt [ap_boot_idtr]
  mov rax, [ap_boot_cr3]
  mov cr3, rax

  movzx rax, word [ap_boot_cs]
  movzx rbx, word [ap_boot_ds]

  push rbx
  push ap_boot_64_enter_kernel

ap_boot_64_enter_kernel:
  

ap_boot_temp_gdtr:
  .2byte 8 * 2 - 1
  .4byte ap_boot_gdt - 8

; Code: 0x08
; Data: 0x10
ap_boot_gdt:
  .8byte 0x00A09A0000000000
  .8byte 0x0000920000000000

ap_boot_end:

ap_boot_cs:
  .2byte 0
ap_boot_ds:
  .2byte 0
ap_boot_cr3:
  .8byte 0
ap_boot_gdtr:
  .2byte 0
  .8byte 0
ap_boot_idtr:
  .2byte 0
  .8byte 0

.section .text
ap_boot_store:
  sidt [rel ap_boot_gdtr]
  sgdt [rel ap_boot_idtr]
  mov  rax, cr3
  mov  [rel ap_boot_cr3], rax
  push cs
  pop [rel ap_boot_cs]
  push ds
  pop [rel ap_boot_ds]
  ret
