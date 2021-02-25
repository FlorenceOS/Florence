const ports = @import("ports.zig");

pub fn disable() void {
  // Remmapping PIC
  ports.outb(0x20, 0x11);
  ports.outb(0xa0, 0x11);
  ports.outb(0x21, 0x20);
  ports.outb(0xa1, 0x28);
  ports.outb(0x21, 0b0000_0100);
  ports.outb(0xa1, 0b0000_0010);
  ports.outb(0x21, 0x01);
  ports.outb(0xa1, 0x01);
  // Masking out all PIC interrupts
  ports.outb(0x21, 0xFF);
  ports.outb(0xa1, 0xFF);
}
