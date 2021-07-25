ENTRY(_start)

PHDRS {
  none   PT_NULL FLAGS(0);
  text   PT_LOAD FLAGS((1 << 2) | (1 << 0) /* Readable | Executable */);
  stk    PT_LOAD FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
  data   PT_LOAD FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
  rodata PT_LOAD FLAGS((1 << 2)            /* Readable */);
}

SECTIONS {
  .stivalehdr  0 : { KEEP(*(.stivalehdr)) }:none
  .stivale2hdr 0 : { KEEP(*(.stivale2hdr)) }
  .rela.dyn    0 : { KEEP(*(.rela*)) }

  . = 0xFFFFFFFF80100000;

  __kernel_begin = .;
  __kernel_text_begin = .;
  .text . : {
    *(.text*)
  }:text
  . = ALIGN(64K);
  __kernel_text_end = .;

  . += 64K;
  .stk . : {
    __bootstrap_stack_bottom = .;
    KEEP(*(.bss.stk))
    __bootstrap_stack_top = .;
  }:stk
  . = ALIGN(64K);

  . += 64K;

  __kernel_rodata_begin = .;
  .rodata . : {
    KEEP(*(.rodata.stivale))
    *(.rodata*)

    /* https://github.com/ziglang/zig/issues/7962 */

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
  }:rodata
  . = ALIGN(64K);
  __kernel_rodata_end = .;

  __kernel_data_begin = .;
  .data . : {
    *(.data*)
  }:data

  . = ALIGN(16);

  .bss . : {
    *(.bss*)
  }
  . = ALIGN(64K);
  __kernel_data_end = .;

  __kernel_end = .;
}
