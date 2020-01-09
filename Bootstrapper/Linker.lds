OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i386)

SectorBytes =  0x200;
SectionAlign = 16;

SECTIONS {
  . = 0x7E00;

  .text :{
    *(.BootstrapHeader)
    . = ALIGN(SectorBytes);
    BootstrapStart = .;
    . = ALIGN(SectionAlign);
    *(.BootstrapEntry)
    . = ALIGN(SectionAlign);

    constructorsStart = .;
    KEEP(*( .init_array ));
    KEEP(*(SORT_BY_INIT_PRIORITY( .init_array.* )));
    constructorsEnd = .;

    . = ALIGN(SectionAlign);

    destructorsStart = .;
    KEEP(*( .fini_array ));
    KEEP(*(SORT_BY_INIT_PRIORITY( .fini_array.* )));
    destructorsEnd = .;

    . = ALIGN(SectionAlign);

    *(.data*)
    . = ALIGN(SectionAlign);
    *(.text*)
    . = ALIGN(SectionAlign);
    *(.rodata*)
    . = ALIGN(SectionAlign);
    *(.bss*)
    . = ALIGN(SectionAlign);

    BootstrapEnd = .;
    . = ALIGN(SectorBytes);
  } = 0x00

  /DISCARD/ : {
    *(*)
  }
}

ENTRY(bootstrapStart)
BootstrapSize = BootstrapEnd - BootstrapStart;
/* Round the number of sectors needed up */
BootstrapSectors = (BootstrapSize + SectorBytes - 1) / SectorBytes;
