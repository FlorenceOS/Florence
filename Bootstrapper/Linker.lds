OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i386)

ENTRY(bootstrapStart)

SectorBytes =  0x200;

SECTIONS {
  . = 0x7E00;

  .text :{
    KEEP(*(.BootstrapHeader))
    . = ALIGN(SectorBytes);
    BootstrapStart = .;
    *(.BootstrapEntry)

    . = ALIGN(4);
    constructorsStart = .;
    KEEP(*(.init_array));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)));
    constructorsEnd = .;

    *(.data*)
    *(.text*)
    *(.rodata*)
    *(.bss*)

    . = ALIGN(SectorBytes);
    BootstrapEnd = .;
  } = 0x00
}

BootstrapSize = BootstrapEnd - BootstrapStart;
BootstrapSectors = BootstrapSize / SectorBytes;
