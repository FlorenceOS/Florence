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
    KEEP(*(SORT_BY_INIT_PRIORITY(.ctors)));
    KEEP(*(SORT_BY_INIT_PRIORITY(.ctors.*)));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array)));
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)));
    constructorsEnd = .;

    *(.data*)
    *(.text*)
    *(.rodata*)
    *(.bss*)
    *(.kernel*)
    . = ALIGN(4K);
    KernelLoaderEnd = .;

    KernelLoaderSize = KernelLoaderEnd - KernelLoaderBegin;
    /* Give size in pages */
    KernelLoaderPages = KernelLoaderSize / 4K;
  } = 0x00
}
