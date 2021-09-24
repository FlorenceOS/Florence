usingnamespace @import("root").preamble;

fn ProtectedPutchar(comptime putch_func: anytype) type {
    return struct {
        is_inside: bool = false,

        pub fn putch(self: *@This(), ch: u8) void {
            if (self.is_inside)
                return;

            self.is_inside = true;
            defer self.is_inside = false;
            putch_func(ch);
        }
    };
}

var log_lock: os.thread.Spinlock = .{};
var lock_owner: ?*os.platform.smp.CoreData = null;
var platform: ProtectedPutchar(os.platform.debugputch) = .{};
var mmio_serial: ProtectedPutchar(os.drivers.output.mmio_serial.putch) = .{};
var vesa_log: ProtectedPutchar(os.drivers.output.vesa_log.putch) = .{};
var vga_log: ProtectedPutchar(os.drivers.output.vga_log.putch) = .{};

pub noinline fn putch(ch: u8) void {
    if (ch == 0)
        return;

    platform.putch(ch);
    mmio_serial.putch(ch);
    vesa_log.putch(ch);
    if (os.platform.arch == .x86_64) {
        vga_log.putch(ch);
    }
}
