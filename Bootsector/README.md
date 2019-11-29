# Florence bootsector
Reads in second stage header from the sector directly following the first boot sector
Note: We don't do partitions here. We treat disks as memory.

It will detect any read errors and print them out on the screen in awesome hexadecimal.

A sector is a `0x200 = 512` byte block of data on disk.

All values are little endian.

# Second stage specification
* Header:
  | Offset | Size (bytes) | Value                      |
  |:-------|:-------------|:---------------------------|
  |`0`     |`4`           |`0xb16d1cc5`                |
  |`4`     |`2`           |`0x6969`                    |
  |`6`     |`2`           |`0x1337`                    |
  |`8`     |`1`           |`# of sectors in next stage`|

If the values match, it will load however many sectors you've specified in the header of contigous storage after the header to the memory base of `0x7E00`, then jumps there.

# Provided by the first stage bootloader:
* GDT
  * `0x00`: Null
  * `0x08`: 16 Bit code segment
  * `0x10`: 16 Bit data segment
  * `0x18`: 32 Bit code segment
  * `0x20`: 32 Bit data segment
  * `0x28`: 64 Bit code segment
  * `0x30`: 64 Bit data segment

* `cs = 0x08`, the other selectors are `= 0x10`.
* Some (small) stack is set.
* Nothing is reserved above you by the first stage, but you still have to watch out for what the platform wants to use.
* All the memory below your program is reserved as long as you're either using the provided GDT *OR* stack.

Note that some PCs only support loading up to `0x7f = 127` sectors at a time. We are limited by those restrictions too, but we won't attempt to load less than you've specified in smaller chunks. If you want to work on those computers, you better have a smaller second stage.
