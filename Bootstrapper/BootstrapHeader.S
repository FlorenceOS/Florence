.section .BootstrapHeader
.long 0xb16d1cc5
.word 0x6969
.word 0x1337
.extern BootstrapSectors
.byte   BootstrapSectors
.global desiredWidth
        desiredWidth: .word 1440
.global desiredHeight
        desiredHeight: .word 900
