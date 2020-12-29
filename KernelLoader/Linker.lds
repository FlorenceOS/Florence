OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

SectorBytes = 0x200;

SECTIONS {
  . = 1024M;

  .text :{
    KernelLoaderBegin = .;
    KEEP(*(.KernelLoaderHeader))

    . = ALIGN(8);
    constructorsStart = .;
    KEEP(*(.init_array));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)));
    constructorsEnd = .;

    *(.data*)
    *(.text*)
    *(.rodata*)
    *(.bss*)
    *(.kernel*)
    . = ALIGN(4K);
    KernelLoaderEnd = .;
  } = 0x00

  .stivalehdr :{
    KEEP(*(.stivalehdr));
  }
}

KernelLoaderSize = KernelLoaderEnd - KernelLoaderBegin;
KernelLoaderPages = KernelLoaderSize / 4K;
