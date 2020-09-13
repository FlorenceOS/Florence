.section .text
.global _start
_start:
.extern baremetal_virt_main
  ADR X18, stack_top
  MOV SP, X18
  B baremetal_virt_main

.section .bss
.balign 16
stack_bottom:
.zero 4096 - 16
stack_top:
.zero 16
