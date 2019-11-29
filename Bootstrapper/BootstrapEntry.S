.intel_syntax noprefix

.section .BootstrapEntry
.code16
.global bootstrapStart
        bootstrapStart:
  # WOHOOO WE MADE IT

  # We're not just yet in 32 bit mode,
  # as we have some data we would like to fetch first.
  jmp .

.extern mainstrap
  call  mainstrap

