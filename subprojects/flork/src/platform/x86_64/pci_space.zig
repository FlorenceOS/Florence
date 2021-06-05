const ports = @import("ports.zig");
const pci = @import("root").os.platform.pci;

fn request(addr: pci.Addr, offset: pci.regoff) void {
    const val = 1 << 31 | @as(u32, offset) | @as(u32, addr.function) << 8 | @as(u32, addr.device) << 11 | @as(u32, addr.bus) << 16;

    ports.outl(0xCF8, val);
}

pub fn read(comptime T: type, addr: pci.Addr, offset: pci.regoff) T {
    request(addr, offset);
    return ports.in(T, 0xCFC + @as(u16, offset % 4));
}

pub fn write(comptime T: type, addr: pci.Addr, offset: pci.regoff, value: T) void {
    request(addr, offset);
    ports.out(T, 0xCFC + @as(u16, offset % 4), value);
}
