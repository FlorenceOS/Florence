OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i8086)

ENTRY(loaderStart)

SECTIONS {
  . = loadAddress;
  .text : {
    textstart = .;
    *(.Bootloader)
    . = textstart + 0x1BE;
    *(.DummyPartitionTable)
    . = textstart + 0x1FE;
    *(.BootSignature)
  } = 0x00
}
