const ports = @import("ports.zig");

fn wait() void {
    ports.outb(0x80, undefined);
}

pub fn disable() void {
    // Remmapping PIC
    ports.outb(0x20, 0x11);
    wait();
    ports.outb(0xa0, 0x11);
    wait();
    ports.outb(0x21, 0x20);
    wait();
    ports.outb(0xa1, 0x28);
    wait();
    ports.outb(0x21, 0b0000_0100);
    wait();
    ports.outb(0xa1, 0b0000_0010);
    wait();
    ports.outb(0x21, 0x01);
    wait();
    ports.outb(0xa1, 0x01);
    wait();
    // Masking out all PIC interrupts
    ports.outb(0x21, 0xFF);
    ports.outb(0xa1, 0xFF);
    wait();
}
