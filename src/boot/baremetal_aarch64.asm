.section .text
.global _start
_start:
.extern baremetal_main
  ADR X30, stack_top
  MOV SP, X30
  BL baremetal_main
1:
  WFI
  B 1b

.section .bss
stack_bottom:
.zero 1024 - 16
stack_top:
.zero 16
