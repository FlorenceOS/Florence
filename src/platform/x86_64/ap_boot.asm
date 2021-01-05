.intel_syntax noprefix

.global ap_boot_begin
.global ap_boot_end

.section .data
.code16
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
  ljmp 0x08,ap_boot_64

.code64
ap_boot_64:
  lgdt [ap_boot_gdtr]
  lidt [ap_boot_idtr]
  mov rax, [ap_boot_cr3]
  mov cr3, rax

  movzx rax, word ptr [ap_boot_cs]
  movzx rbx, word ptr [ap_boot_ds]

  mov ds, bx
  mov es, bx
  mov fs, bx
  mov gs, bx

  push [ap_boot_rip] // rip
  push rax // cs
  pushf    // eflags
  push 0   // rsp hmmm
  push rbx // ss

  iretq

ap_boot_temp_gdtr:
  .2byte 8 * 2 - 1
  .4byte ap_boot_gdt - 8

// Code: 0x08
// Data: 0x10
ap_boot_gdt:
  .8byte 0x00A09A0000000000
  .8byte 0x0000920000000000

ap_boot_end:

ap_boot_rip:
  .8byte 0
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

.global ap_boot_store

.section .text
ap_boot_store:
  mov [ap_boot_rip + rip], rdi
  sidt [ap_boot_gdtr + rip]
  sgdt [ap_boot_idtr + rip]
  mov rax, cr3
  mov [ap_boot_cr3 + rip], rax
  mov ax, cs
  mov [ap_boot_cs + rip], ax
  mov ax, ds
  mov [ap_boot_ds + rip], ax
  ret
