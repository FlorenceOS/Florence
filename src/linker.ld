ENTRY(_start)

PHDRS {
  none   PT_NULL FLAGS(0);
  text   PT_LOAD FLAGS((1 << 2) | (1 << 0) /* Readable | Executable */);
  data   PT_LOAD FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
  rodata PT_LOAD FLAGS((1 << 2)            /* Readable */);
}

SECTIONS {
  .stivalehdr : {
    KEEP(*(.stivalehdr))
  }: none

  . = 1M;

  .text : ALIGN(16K) {
    *(.text)
  }:text

  .rodata : ALIGN(16K) {
    *(.rodata)
  }:rodata

  .data : ALIGN(16K) {
    *(.data)
  }:data

  .bss : ALIGN(16K) {
    *(.bss)
  }:data
}
