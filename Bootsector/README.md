# Florence bootsector
**Note: We don't do partitions here. We treat disks as memory.**
In the case of any read errors, it will print them out on the screen in awesome hexadecimal.
A sector is a `0x200 = 512` byte block of data on disk.
All values are little endian.

# Bootsector specification for second stage
* Reads in second stage header from the sector directly following the first boot sector
* Header:

  | Offset  | Size (bytes) | Value                      |
  |:-------|:-------------|:---------------------------|
  |`0`     |`4`           |`0xb16d1cc5`                |
  |`4`     |`2`           |`0x6969`                    |
  |`6`     |`2`           |`0x1337`                    |
  |`8`     |`1`           |`# of sectors in next stage`|  
* If the values match, it will load however many sectors you've specified in the header of contigous storage after the header to the memory base of `0x7E00`, then jumps there.

# Provided by the first stage bootloader:
* Loaded GDT: All non-null descriptors have an offset of 0 and the max possible limit and granularity for the number of bits. 

  | Selector | Type | Bits | Ring | Permissions |
  |:---------|:-----|:-----|:-----|:------------|
  |`0x00`    | Null |`N/A` |`N/A` |`N/A`        |
  |`0x08`    | Code | 16   |`0`   |`RX`         |
  |`0x10`    | Data | 16   |`0`   |`RW`         |
  |`0x18`    | Code | 32   |`0`   |`RX`         |
  |`0x20`    | Data | 32   |`0`   |`RW`         |
  |`0x28`    | Code | 64   |`0`   |`RX`         |
  |`0x30`    | Data | 64   |`0`   |`RW`         |
* All selectors start at `0x00`.
* Some (albeit small) stack is set.
* Nothing is reserved above you by the first stage, but you still have to watch out for what the platform wants to use.
* All the memory below your program is reserved as long as you're using either the provided GDT *OR* stack. If you have stopped using them, you are free to use this memory too.
* Interrupts disabled
* a20 enabled

Note that this bootsector only can load a second stage up to a size of about `0xFD00` (barely less than 64K), so don't make it too large.
