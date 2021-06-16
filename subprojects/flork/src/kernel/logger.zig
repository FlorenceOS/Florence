usingnamespace @import("root").preamble;

const fmt = std.fmt;
const range = lib.util.range.range;

const Printer = struct {
    pub fn writeAll(self: *const Printer, str: []const u8) !void {
        try @call(.{ .modifier = .never_inline }, printString, .{str});
    }

    pub fn print(self: *const Printer, comptime format: []const u8, args: anytype) !void {
        logWithoutLocking(format, args);
    }

    pub fn writeByteNTimes(self: *const Printer, val: u8, num: usize) !void {
        var i: usize = 0;
        while (i < num) : (i += 1) {
            putch(val);
        }
    }

    pub const Error = anyerror;
};

const LogLock = struct {
    lock: ?@typeInfo(@TypeOf(log_lock.lock)).BoundFn.return_type.?,
};

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

fn logWithoutLocking(comptime format: []const u8, args: anytype) void {
    var printer = Printer{};
    fmt.format(printer, format, args) catch unreachable;
}

fn printString(str: []const u8) !void {
    for (str) |c| {
        putch(c);
    }
}

fn putch(ch: u8) void {
    if (ch == 0)
        return;

    platform.putch(ch);
    mmio_serial.putch(ch);
    vesa_log.putch(ch);
    if (os.platform.arch == .x86_64) {
        vga_log.putch(ch);
    }
}

pub fn getLogLock() LogLock {
    const current_cpu = os.platform.thread.get_current_cpu();

    if (@atomicLoad(?*os.platform.smp.CoreData, &lock_owner, .Acquire) == current_cpu) {
        return .{ .lock = null };
    }

    defer @atomicStore(?*os.platform.smp.CoreData, &lock_owner, current_cpu, .Release);
    return .{ .lock = log_lock.lock() };
}

pub fn releaseLogLock(ll: LogLock) void {
    if (ll.lock) |l| {
        @atomicStore(?*os.platform.smp.CoreData, &lock_owner, null, .Release);
        log_lock.unlock(l);
    }
}

pub fn log(comptime format: []const u8, args: anytype) void {
    const l = getLogLock();
    defer releaseLogLock(l);

    return logWithoutLocking(format, args);
}

pub fn hexdumpObj(val: anytype) void {
    hexdump(@ptrCast([*]u8, val)[0..@sizeOf(@TypeOf(val.*))]);
}

pub fn hexdump(in_bytes: []const u8) void {
    const l = os.getLogLock();
    defer os.releaseLogLock(l);

    var bytes = in_bytes;
    while (bytes.len != 0) {
        log("{X:0>16}: ", .{@ptrToInt(bytes.ptr)});

        inline for (range(0x10)) |offset| {
            if (offset < bytes.len) {
                const value = bytes[offset];
                log("{X:0>2}{c}", .{ value, if (offset == 7) '-' else ' ' });
            } else {
                log("   ", .{});
            }
        }

        inline for (range(0x10)) |offset| {
            if (offset < bytes.len) {
                const value = bytes[offset];
                if (0x20 <= value and value < 0x7F) {
                    log("{c}", .{value});
                } else {
                    log(".", .{});
                }
            } else {
                log(" ", .{});
            }
        }

        log("\n", .{});

        if (bytes.len < 0x10)
            return;

        bytes = bytes[0x10..];
    }
}
