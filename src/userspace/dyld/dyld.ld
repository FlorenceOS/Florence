ENTRY(_start)

PHDRS {
  none   PT_NULL FLAGS(0);
  blob   PT_LOAD FLAGS((1 << 2) | (1 << 1) | (1 << 0));
}

SECTIONS {
  .rela.dyn : { KEEP(*(.rela*)) }

  . = 0x1000;

  __dyld_base = .;

  .blob : ALIGN(64K) {
    *(.text*)
    *(.rodata*)
    *(.data*)
    *(.bss*)
  }:blob

  __dyld_end = .;

  .rodata : ALIGN(64K) {
    /*__debug_info_start = .;
    KEEP(*(.debug_info))
    __debug_info_end = .;
    __debug_abbrev_start = .;
    KEEP(*(.debug_abbrev))
    __debug_abbrev_end = .;
    __debug_str_start = .;
    KEEP(*(.debug_str))
    __debug_str_end = .;
    __debug_line_start = .;
    KEEP(*(.debug_line))
    __debug_line_end = .;
    __debug_ranges_start = .;
    KEEP(*(.debug_ranges))
    __debug_ranges_end = .;*/
  }
}
