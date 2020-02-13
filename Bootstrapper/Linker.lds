OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i386)

SectorBytes =  0x200;

SECTIONS {
  . = 0x7E00;

  .text :{
    *(.BootstrapHeader)
    . = ALIGN(SectorBytes);
    BootstrapStart = .;
    *(.BootstrapEntry)

    constructorsStart = .;
    KEEP(*(SORT_BY_INIT_PRIORITY(.ctors)));
    KEEP(*(SORT_BY_INIT_PRIORITY(.ctors.*)));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array)));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)));
    constructorsEnd = .;

    *(.data*)
    *(.text*)
    *(.rodata*)
    *(.bss*)

    BootstrapEnd = .;
    . = ALIGN(SectorBytes);
  } = 0x00
}

ENTRY(bootstrapStart)
BootstrapSize = BootstrapEnd - BootstrapStart;
/* Round the number of sectors needed up */
BootstrapSectors = (BootstrapSize + SectorBytes - 1) / SectorBytes;
