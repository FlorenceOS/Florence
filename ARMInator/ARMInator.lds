OUTPUT_FORMAT(elf64-littleaarch64)
OUTPUT_ARCH(aarch64)
ENTRY(_start)

SECTIONS {
  .text : {
    KEEP(*(.entry*))
    *(.rodata*)
    *(.data*)
    *(.bss*)
    *(.got*)
    *(.text*)
    . = ALIGN(0x4000);
  } = 0x00

  .shstrtab : {
    *(.shstrtab)
  }
}
