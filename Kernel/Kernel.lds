OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

PHDRS {
    text PT_LOAD;
    data PT_LOAD;
    rodata PT_LOAD;
}

SECTIONS {
  /* X sections*/
  . = 0;
  .text :{ *(.text*) } :text

  /* R/W data sections */
  .data ALIGN(4K):{
    constructorsStart = .;
    KEEP(*(.ctors));
    KEEP(*(SORT_BY_INIT_PRIORITY(.ctors.*)));
    KEEP(*(.init_array));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)));
    constructorsEnd = .;
    *(.data* .got*)
  } :data

  .rela.dyn :{ *(.rela*) } :data
  .shstrtab :{ *(.shstrtab*) } :data

  /* .bss needs to be last to not be file backed */
  .bss :{ *(.bss*) } :data

  /* R data sections*/
  .rodata ALIGN(4K):{ *(.rodata*) } :rodata

  /DISCARD/ :{
    *(*)
  }
}
