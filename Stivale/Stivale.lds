OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)

ENTRY(stivale_entry)

SectorBytes = 0x200;

SECTIONS {
  . = 1M;

  .stivalehdr ALIGN(4K) :{
    KEEP(*(.stivalehdr));
  }

  .text ALIGN(4K) :{
    *(.text*)
  }

  .rodata ALIGN(4K) :{
    constructorsStart = .;
    KEEP(*(.init_array));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)));
    constructorsEnd = .;
    *(.rodata*)
  }

  .data ALIGN(4K) :{
    *(.data*)
  }

  .bss ALIGN(4K) :{
    *(.bss*)
  }
}
