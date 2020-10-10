.global ap_boot_begin
.global ap_boot_end

.section .data
.bits 16
ap_boot_begin:
  lgdt [ap_boot_temp_gdtr - ap_boot_begin]
  mov eax, [ap_boot_cr3 - ap_boot_begin]
  mov cr3, eax

  mov eax, cr4
  or al, (1 << 5)
  mov cr4, eax

  mov ecx, 0xc0000080
  or ax, (1 << 8)
  wrmsr

  mov eax, 0x80000011
  mov cr0, eax
  jmp 0x08:(ap_boot_64 - ap_boot_begin)

.bits 64
ap_boot_64:
  lgdt []
  jmp .

ap_boot_temp_gdtr:
  .2byte 8 * 2 - 1
  .4byte ap_boot_gdt - ap_boot_begin - 8

; Code: 0x08
; Data: 0x10
ap_boot_gdt:
  .8byte 0x00A09A0000000000
  .8byte 0x0000920000000000

ap_boot_cr3:
  .8byte 0
ap_boot_gdtr:
  .2byte 0
  .8byte 0
ap_boot_idtr:
  .2byte 0
  .8byte 0

ap_boot_end:

.section .text
ap_boot_store:
  sidt [rel ap_boot_gdtr]
  sgdt [rel ap_boot_idtr]
  mov  rax, cr3
  mov  [rel ap_boot_cr3], rax
  ret
