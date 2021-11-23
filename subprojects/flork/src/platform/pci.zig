usingnamespace @import("root").preamble;

const std = @import("std");
const lib = @import("lib");
const config = @import("config");

const log = lib.output.log.scoped(.{
    .prefix = "platform/pci",
    .filter = .info,
});

const paging = os.memory.paging;

const range = lib.util.range.range;

pub const Handler = struct { function: fn (*os.platform.InterruptFrame, u64) void, context: u64 };

var handlers: [0x100]Handler = undefined;

pub const Cap = struct {
    addr: Addr,
    off: u8,
    pub fn next(self: *Cap) void {
        self.off = self.addr.read(u8, self.off + 0x01);
    }
    pub fn vndr(self: *const Cap) u8 {
        return self.addr.read(u8, self.off + 0x00);
    }
    pub fn read(self: *const Cap, comptime T: type, off: regoff) T {
        return self.addr.read(T, self.off + off);
    }
    pub fn write(self: *const Cap, comptime T: type, off: regoff, value: T) void {
        self.addr.write(T, self.off + off, value);
    }
};

pub const Addr = struct {
    bus: u8,
    device: u5,
    function: u3,

    const vendor_id = cfgreg(u16, 0x00);
    const device_id = cfgreg(u16, 0x02);
    const command = cfgreg(u16, 0x04);
    const status = cfgreg(u16, 0x06);
    const prog_if = cfgreg(u8, 0x09);
    const header_type = cfgreg(u8, 0x0E);
    const base_class = cfgreg(u8, 0x0B);
    const sub_class = cfgreg(u8, 0x0A);
    const secondary_bus = cfgreg(u8, 0x19);
    const cap_ptr = cfgreg(u8, 0x34);
    const int_line = cfgreg(u8, 0x3C);
    const int_pin = cfgreg(u8, 0x3D);

    pub fn cap(self: Addr) Cap {
        return .{ .addr = self, .off = self.cap_ptr().read() & 0xFC };
    }

    pub fn barinfo(self: Addr, bar_idx: u8) BarInfo {
        var orig: u64 = self.read(u32, 0x10 + bar_idx * 4) & 0xFFFFFFF0;
        self.write(u32, 0x10 + bar_idx * 4, 0xFFFFFFFF);
        var pci_out = self.read(u32, 0x10 + bar_idx * 4);
        const is64 = ((pci_out & 0b110) >> 1) == 2; // bits 1:2, bar type (0 = 32bit, 1 = 64bit)

        self.write(u32, 0x10 + bar_idx * 4, @truncate(u32, orig));

        // The BARs can be either 64 or 32 bit, but the trick works for both
        var response: u64 = @as(u64, pci_out & 0xFFFFFFF0);
        if (is64) {
            orig |= @as(u64, self.read(u32, 0x14 + bar_idx * 4)) << 32;
            self.write(u32, 0x14 + bar_idx * 4, 0xFFFFFFFF); // 64bit bar = two 32-bit bars
            response |= @as(u64, self.read(u32, 0x14 + bar_idx * 4)) << 32;
            self.write(u32, 0x14 + bar_idx * 4, @truncate(u32, orig >> 32));
            return .{ .phy = orig, .size = ~response +% 1 };
        } else {
            return .{ .phy = orig, .size = (~response +% 1) & 0xFFFFFFFF };
        }
    }

    pub fn read(self: Addr, comptime T: type, offset: regoff) T {
        if (pci_mmio[self.bus] != null) {
            const buf = mmio(self, offset)[0..@sizeOf(T)].*;
            return std.mem.readIntLittle(T, &buf);
        }
        if (@hasDecl(os.platform, "pci_space"))
            return os.platform.pci_space.read(T, self, offset);
        @panic("No pci module!");
    }

    pub fn write(self: Addr, comptime T: type, offset: regoff, value: T) void {
        if (pci_mmio[self.bus] != null) {
            var buf: [@sizeOf(T)]u8 = undefined;
            std.mem.writeIntLittle(T, &buf, value);
            mmio(self, offset)[0..@sizeOf(T)].* = buf;
            return;
        }
        if (@hasDecl(os.platform, "pci_space"))
            return os.platform.pci_space.write(T, self, offset, value);
        @panic("No pci module!");
    }

    pub fn format(self: Addr, fmt: anytype) void {
        fmt("[{0X}:{0X}:{0X}]", .{ self.bus, self.device, self.function });
        fmt("{{{0X}:{0X}}} ", .{ self.vendor_id().read(), self.device_id().read() });
        fmt("({0X}:{0X}:{0X})", .{ self.base_class().read(), self.sub_class().read(), self.prog_if().read() });
    }
};

pub const regoff = u8;

fn mmio(addr: Addr, offset: regoff) [*]volatile u8 {
    return @ptrCast([*]volatile u8, pci_mmio[addr.bus].?) + (@as(u64, addr.device) << 15 | @as(u64, addr.function) << 12 | @as(u64, offset));
}

const BarInfo = struct {
    phy: u64,
    size: u64,
};

fn function_scan(addr: Addr) void {
    if (addr.vendor_id().read() == 0xFFFF)
        return;

    const l = log.start(.info, "{} ", .{addr});

    switch (addr.base_class().read()) {
        else => {
            log.finish(.info, "Unknown class!", .{}, l);
        },
        0x00 => {
            switch (addr.sub_class().read()) {
                else => {
                    log.finish(.info, "Unknown unclassified device!", .{}, l);
                },
            }
        },
        0x01 => {
            switch (addr.sub_class().read()) {
                else => {
                    log.finish(.info, "Unknown storage controller!", .{}, l);
                },
                0x06 => {
                    log.finish(.info, "AHCI controller", .{}, l);
                    os.drivers.block.ahci.registerController(addr);
                },
                0x08 => {
                    switch (addr.prog_if().read()) {
                        else => {
                            log.finish(.info, "Unknown non-volatile memory controller!", .{}, l);
                        },
                        0x02 => {
                            log.finish(.info, "NVMe controller", .{}, l);
                            os.drivers.block.nvme.registerController(addr);
                        },
                    }
                },
            }
        },
        0x02 => {
            switch (addr.sub_class().read()) {
                else => {
                    log.finish(.info, "Unknown network controller!", .{}, l);
                },
                0x00 => {
                    if (addr.vendor_id().read() == 0x8086 and addr.device_id().read() == 0x100E) {
                        log.finish(.info, "E1000 controller", .{}, l);
                        os.drivers.net.e1000.registerController(addr);
                    } else {
                        log.finish(.info, "Unknown ethernet controller", .{}, l);
                    }
                },
                0x80 => {
                    log.finish(.info, "Other network controller", .{}, l);
                },
            }
        },
        0x03 => {
            if (addr.vendor_id().read() == 0x1AF4 or addr.device_id().read() == 0x1050) {
                log.finish(.info, "Virtio display controller", .{}, l);
                os.drivers.gpu.virtio_gpu.registerController(addr);
            } else switch (addr.sub_class().read()) {
                else => {
                    log.finish(.info, "Unknown display controller!", .{}, l);
                },
                0x00 => {
                    log.finish(.info, "VGA compatible controller", .{}, l);
                },
            }
        },
        0x04 => {
            switch (addr.sub_class().read()) {
                else => {
                    log.finish(.info, "Unknown multimedia controller!", .{}, l);
                },
                0x03 => {
                    log.finish(.info, "Audio device", .{}, l);
                },
            }
        },
        0x06 => {
            switch (addr.sub_class().read()) {
                else => {
                    log.finish(.info, "Unknown bridge device!", .{}, l);
                },
                0x00 => {
                    log.finish(.info, "Host bridge", .{}, l);
                },
                0x01 => {
                    log.finish(.info, "ISA bridge", .{}, l);
                },
                0x04 => {
                    log.cont(.info, "PCI-to-PCI bridge", .{}, l);
                    if ((addr.header_type().read() & 0x7F) != 0x01) {
                        log.finish(.info, ": Not PCI-to-PCI bridge header type!", .{}, l);
                    } else {
                        const secondary_bus = addr.secondary_bus().read();
                        log.finish(.info, ", recursively scanning bus {0X}", .{secondary_bus}, l);
                        bus_scan(secondary_bus);
                    }
                },
            }
        },
        0x0c => {
            switch (addr.sub_class().read()) {
                else => {
                    log.finish(.info, "Unknown serial bus controller!", .{}, l);
                },
                0x03 => {
                    switch (addr.prog_if().read()) {
                        else => {
                            log.finish(.info, "Unknown USB controller!", .{}, l);
                        },
                        0x20 => {
                            log.finish(.info, "USB2 EHCI controller", .{}, l);
                        },
                        0x30 => {
                            log.finish(.info, "USB3 XHCI controller", .{}, l);
                            os.drivers.usb.xhci.registerController(addr);
                        },
                    }
                },
            }
        },
    }
}

fn laihost_addr(seg: u16, bus: u8, slot: u8, fun: u8) Addr {
    return .{
        .bus = bus,
        .device = @intCast(u5, slot),
        .function = @intCast(u3, fun),
    };
}

export fn laihost_pci_writeb(seg: u16, bus: u8, slot: u8, fun: u8, offset: u16, value: u8) void {
    laihost_addr(seg, bus, slot, fun).write(u8, @intCast(u8, offset), value);
}

export fn laihost_pci_readb(seg: u16, bus: u8, slot: u8, fun: u8, offset: u16) u8 {
    return laihost_addr(seg, bus, slot, fun).read(u8, @intCast(u8, offset));
}

export fn laihost_pci_writew(seg: u16, bus: u8, slot: u8, fun: u8, offset: u16, value: u16) void {
    laihost_addr(seg, bus, slot, fun).write(u16, @intCast(u8, offset), value);
}

export fn laihost_pci_readw(seg: u16, bus: u8, slot: u8, fun: u8, offset: u16) u16 {
    return laihost_addr(seg, bus, slot, fun).read(u16, @intCast(u8, offset));
}

export fn laihost_pci_writed(seg: u16, bus: u8, slot: u8, fun: u8, offset: u16, value: u32) void {
    laihost_addr(seg, bus, slot, fun).write(u32, @intCast(u8, offset), value);
}

export fn laihost_pci_readd(seg: u16, bus: u8, slot: u8, fun: u8, offset: u16) u32 {
    return laihost_addr(seg, bus, slot, fun).read(u32, @intCast(u8, offset));
}

fn device_scan(bus: u8, device: u5) void {
    const nullfunc: Addr = .{ .bus = bus, .device = device, .function = 0 };

    if (nullfunc.vendor_id().read() == 0xFFFF)
        return;

    function_scan(nullfunc);

    // Return already if this isn't a multi-function device
    if (nullfunc.header_type().read() & 0x80 == 0)
        return;

    inline for (range((1 << 3) - 1)) |function| {
        function_scan(.{ .bus = bus, .device = device, .function = function + 1 });
    }
}

fn bus_scan(bus: u8) void {
    if (!config.kernel.pci.enable)
        return;

    // We can't scan this bus
    if (!@hasDecl(os.platform, "pci_space") and pci_mmio[bus] == null)
        return;

    inline for (range(1 << 5)) |device| {
        device_scan(bus, device);
    }
}

pub fn init_pci() !void {
    bus_scan(0);
}

pub fn register_mmio(bus: u8, physaddr: u64) !void {
    pci_mmio[bus] = os.platform.phys_ptr([*]u8).from_int(physaddr).get_uncached()[0 .. 1 << 20];
}

var pci_mmio: [0x100]?*[1 << 20]u8 linksection(".bss") = undefined;

fn PciFn(comptime T: type, comptime off: regoff) type {
    return struct {
        self: Addr,
        pub fn read(self: @This()) T {
            return self.self.read(T, off);
        }
        pub fn write(self: @This(), val: T) void {
            self.self.write(T, off, val);
        }
    };
}

fn cfgreg(comptime T: type, comptime off: regoff) fn (self: Addr) PciFn(T, off) {
    return struct {
        fn function(self: Addr) PciFn(T, off) {
            return .{ .self = self };
        }
    }.function;
}

pub const PCI_CAP_MSIX_MSGCTRL = 0x02;
pub const PCI_CAP_MSIX_TABLE = 0x04;
pub const PCI_CAP_MSIX_PBA = 0x08;

pub const PCI_COMMAND_BUSMASTER = 1 << 2;
pub const PCI_COMMAND_LEGACYINT_DISABLE = 1 << 10;
