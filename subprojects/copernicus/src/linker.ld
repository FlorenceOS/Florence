ENTRY(_start)

PHDRS {
  none   PT_NULL FLAGS(0);
}

SECTIONS {
  . = 0x30000000 - 32;
  .blob : {
    QUAD(__copernicus_base);
    QUAD(__data_offset);
    QUAD(__rodata_offset);
    . += 8;
    __copernicus_base = .;
    *(.text.entry)
    *(.text*)
    . = ALIGN(4K);
    __data_offset = . - __copernicus_base;
    *(.data*)
    *(.bss*)
    . = ALIGN(4K);
    __rodata_offset = . - __copernicus_base;
    *(.rodata*)
    . = ALIGN(4K);
    __copernicus_end = .;
  }
}
