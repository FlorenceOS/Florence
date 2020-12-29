.section .entry, "ax"
.global _start
_start:
  mrs x0, mpidr_el1
  tst x0, #15
  b.ne 1f

.extern phello
  BL phello
1:
  WFI
  B 1b
