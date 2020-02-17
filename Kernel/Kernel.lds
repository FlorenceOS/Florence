OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

Executable = 1 << 0;
Writeable  = 1 << 1;
Readable   = 1 << 2;

PHDRS {
    text   PT_LOAD FLAGS(Readable | Executable);
    data   PT_LOAD FLAGS(Readable | Writeable);
    rodata PT_LOAD FLAGS(Readable);
}

SECTIONS {
  . = 1M;
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
