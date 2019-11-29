OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i8086)

SectorBytes =  0x200;
loadAddress  = 0x7C00 + SectorBytes;

SECTIONS {
  . = 0x7C00;
  .text : {
    *(.BootstrapHeader)
    . = ALIGN(SectorBytes);
    BootstrapStart = .;
    *(.BootstrapEntry)
    *(.data)
    *(.text)
    *(.rodata)
    *(.bss)
    BootstrapEnd = .;
    . = ALIGN(SectorBytes);
  }
}

ENTRY(bootstrapStart)
BootstrapSize = BootstrapEnd - BootstrapStart;
/* Round the number of sectors needed up */
BootstrapSectors = (BootstrapSize + SectorBytes - 1) / SectorBytes;
