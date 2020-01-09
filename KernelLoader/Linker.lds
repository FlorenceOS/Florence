OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)

SectorBytes = 0x200;

SECTIONS {
  . = 1024M;

  .text :{
    KernelLoaderBegin = .;
    KEEP(*(.KernelLoaderHeader))

    . = ALIGN(8);
    constructorsStart = .;
    KEEP(*( .init_array ));
    . = ALIGN(8);
    KEEP(*(SORT_BY_INIT_PRIORITY( .init_array.* )));
    . = ALIGN(8);
    constructorsEnd = .;

    /* Don't do these
    destructorsStart = .;
    KEEP(*( .fini_array ));
    KEEP(*(SORT_BY_INIT_PRIORITY( .fini_array.* )));
    destructorsEnd = .;

    . = ALIGN(SectionAlign);
    */

    . = ALIGN(8);
    *(.data*)
    . = ALIGN(8);
    *(.text*)
    . = ALIGN(8);
    *(.rodata*)
    . = ALIGN(8);
    *(.bss*)
    . = ALIGN(4K);
    KernelLoaderEnd = .;
  } = 0x00

  /DISCARD/ : {
    *(*)
  }
}

KernelLoaderSize = KernelLoaderEnd - KernelLoaderBegin;
/* Give size in pages */
KernelLoaderSize /= 4K;
