OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

SECTIONS {
  .text :{
    *(.text*)
  }

  . = ALIGN(4K);
  .data :{
    constructorsStart = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.ctors)));
    KEEP(*(SORT_BY_INIT_PRIORITY(.ctors.*)));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array)));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)));
    constructorsEnd = .;
    *(.data*)
  }

  .rodata :{
    *(.rodata*)
    *(.got*)
  }

  .rela.dyn :{
    *(.rela*)
  }

  .shstrtab :{
    *(.shstrtab*)
  }

  .bss :{
    *(.bss*)
  }

  /DISCARD/ :{
    *(*)
  }
}
