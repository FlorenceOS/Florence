usingnamespace @import("root").preamble;

const log = @import("lib").output.log.scoped(.{
    .prefix = "x86_64/serial",
    .filter = .info,
}).write;

const platform = os.platform;
const ports = @import("ports.zig");

var inited = [1]bool{false} ** 4;

pub fn init() void {
    port(1).try_init();
    port(2).try_init();
    port(3).try_init();
    port(4).try_init();
}

pub fn port(comptime port_num: usize) type {
    const io_base: u16 = switch (port_num) {
        1 => 0x3f8,
        2 => 0x2f8,
        3 => 0x3e8,
        4 => 0x2e8,
        else => unreachable,
    };

    return struct {
        pub fn try_init() void {
            if (inited[port_num - 1])
                return;

            // First let's try to detect if the serial port is present
            {
                ports.outb(io_base + 7, 0x00);
                if (ports.inb(io_base + 7) != 0x00)
                    return;
                ports.outb(io_base + 7, 0xff);
                if (ports.inb(io_base + 7) != 0xff)
                    return;
            }

            ports.outb(io_base + 3, 0x80);
            ports.outb(io_base + 0, 0x01);
            ports.outb(io_base + 1, 0x00);
            ports.outb(io_base + 3, 0x03);
            ports.outb(io_base + 2, 0xC7);
            ports.outb(io_base + 4, 0x0B);

            if (ports.inb(io_base + 6) & 0xb0 != 0xb0)
                return;

            // Don't enable any serial ports on x86 for now
            //inited[port_num - 1] = true;

            log(.debug, "Using x86 serial port #{d}", .{port_num});
        }

        pub fn read_ready() bool {
            if (!inited[port_num - 1])
                return false;

            return ports.inb(io_base + 5) & 0x20 != 0;
        }

        pub fn read() u8 {
            if (!inited[port_num - 1])
                @panic("Uninitialized serial read!");

            while (!read_ready()) {
                platform.spin_hint();
            }
            return ports.inb(io_base);
        }

        pub fn try_read() ?u8 {
            if (read_ready())
                return read();
            return null;
        }

        pub fn write_ready() bool {
            if (!inited[port_num - 1])
                return false;

            return ports.inb(io_base + 5) & 0x01 != 0;
        }

        pub fn write(val: u8) void {
            if (!inited[port_num - 1])
                return;

            if (val == '\n')
                write('\r');

            while (!write_ready()) {
                platform.spin_hint();
            }
            ports.outb(io_base, val);
        }
    };
}
