# Florence second stage bootloader
The second stage bootloader conforms to the specifications of the first stage bootloader.
It should:
* Aquire a framebuffer
* Switch to 32 bit mode
* Create a freelist of physical pages in < 4GB
* Create page tables
* Page in physical memory with KASLR
* Switch to 64 bit mode and jump to kernel loader

# Kernel loader specification:
* TBD
