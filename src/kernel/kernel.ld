ENTRY(_start)

PHDRS {
  none   PT_NULL FLAGS(0);
  text   PT_LOAD FLAGS((1 << 2) | (1 << 0) /* Readable | Executable */);
  data   PT_LOAD FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
  rodata PT_LOAD FLAGS((1 << 2)            /* Readable */);
}

SECTIONS {
  . = 0;

  .stivalehdr : {
    KEEP(*(.stivalehdr))
  }: none

  .stivale2hdr : {
    KEEP(*(.stivale2hdr))
  }: none

  .rela.dyn : { KEEP(*(.rela*)) }

  . = 0xFFFFFFFF80100000;

  .text : ALIGN(64K) {
    __kernel_text_begin = .;
    *(.text*)
    __kernel_text_end = .;
  }:text

  .rodata : ALIGN(64K) {
    __kernel_rodata_begin = .;
    KEEP(*(.rodata.stivale))
    *(.rodata*)
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
    __kernel_rodata_end = .;
  }:rodata

  .data : ALIGN(64K) {
    __kernel_data_begin = .;
    *(.data*)
    *(.bss*)
    __kernel_data_end = .;
  }:data

  __kernel_end = .;
}
