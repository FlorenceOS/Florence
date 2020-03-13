OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

PHDRS {
  text   PT_LOAD FLAGS((1 << 2) | (1 << 0) /* Readable | Executable */);
  data   PT_LOAD FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
  rodata PT_LOAD FLAGS((1 << 2)            /* Readable */);
}

/* Start of kernel */
SECTIONS {
  /* X sections*/
  .text : { *(.text*) } :text

  /* R/W data sections */
  .data ALIGN(4K) : {
    constructorsStart = .;
    KEEP(*(.ctors));
    KEEP(*(SORT_BY_INIT_PRIORITY(.ctors.*)));
    KEEP(*(.init_array));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)));
    constructorsEnd = .;
    *(.data* .got*)
  } :data

  .rela.dyn : { *(.rela*) }
  .shstrtab : { *(.shstrtab*) }
  .bss      : { *(.bss*) }

  /* R data sections*/
  .rodata ALIGN(4K) : { *(.rodata*) } :rodata

  /DISCARD/ :{ *(*) }
}

/* End of kernel */
. = ALIGN(4K);
kernelEnd = .;
