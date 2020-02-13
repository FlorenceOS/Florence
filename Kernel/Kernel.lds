OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

SECTIONS {
  . = 1M;
  .text :{
    *(.text*)
  }

  . = ALIGN(4K);
  .data :{
    constructorsStart = .;
    KEEP(*( .ctors* ));
    KEEP(*( .init_array* ));
    constructorsEnd = .;
    *(.data*)
    *(.bss*)
  }

  . = ALIGN(4K);
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

  /DISCARD/ :{
    *(*)
  }
}
