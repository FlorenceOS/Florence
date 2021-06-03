const os = @import("root").os;
const lib = @import("root").lib;
const fmt = @import("std").fmt;
const arch = @import("builtin").arch;

const range = lib.util.range.range;

const Printer = struct {
    pub fn writeAll(self: *const Printer, str: []const u8) !void {
        try @call(.{ .modifier = .never_inline }, print_str, .{str});
    }

    pub fn print(self: *const Printer, comptime format: []const u8, args: anytype) !void {
        log_nolock(format, args);
    }

    pub fn writeByteNTimes(self: *const Printer, val: u8, num: usize) !void {
        var i: usize = 0;
        while (i < num) : (i += 1) {
            putch(val);
        }
    }

    pub const Error = anyerror;
};

var log_lock: os.thread.Spinlock = .{};
var lock_owner: ?*os.platform.smp.CoreData = null;

const LogLock = struct {
    lock: ?@typeInfo(@TypeOf(log_lock.lock)).BoundFn.return_type.?,
};

pub fn get_log_lock() LogLock {
    const current_cpu = os.platform.thread.get_current_cpu();

    if(@atomicLoad(?*os.platform.smp.CoreData, &lock_owner, .Acquire) == current_cpu) {
        return .{ .lock = null };
    }

    defer @atomicStore(?*os.platform.smp.CoreData, &lock_owner, current_cpu, .Release);
    return .{ .lock = log_lock.lock() };
}

pub fn release_log_lock(ll: LogLock) void {
    if(ll.lock) |l| {
        @atomicStore(?*os.platform.smp.CoreData, &lock_owner, null, .Release);
        log_lock.unlock(l);
    }
}

pub fn log(comptime format: []const u8, args: anytype) void {
    const l = get_log_lock();
    defer release_log_lock(l);

    return log_nolock(format, args);
}

fn log_nolock(comptime format: []const u8, args: anytype) void {
    var printer = Printer{};
    fmt.format(printer, format, args) catch unreachable;
}

fn print_str(str: []const u8) !void {
    for (str) |c| {
        putch(c);
    }
}

fn protected_putchar(comptime putch_func: anytype) type {
    return struct {
        is_inside: bool = false,

        pub fn putch(self: *@This(), ch: u8) void {
            if(self.is_inside)
                return;

            self.is_inside = true;
            defer self.is_inside = false;
            putch_func(ch);
        }
    };
}

var platform: protected_putchar(os.platform.debugputch) = .{};
var mmio_serial: protected_putchar(os.drivers.mmio_serial.putch) = .{};
var vesa_log: protected_putchar(os.drivers.vesa_log.putch) = .{};
var vga_log: protected_putchar(os.drivers.vga_log.putch) = .{};

fn putch(ch: u8) void {
    platform.putch(ch);
    mmio_serial.putch(ch);
    vesa_log.putch(ch);
    if (arch == .x86_64) {
        vga_log.putch(ch);
    }
}

pub fn hexdump_obj(val: anytype) void {
    hexdump(@ptrCast([*]u8, val)[0..@sizeOf(@TypeOf(val.*))]);
}

pub fn hexdump(in_bytes: []const u8) void {
    const l = os.get_log_lock();
    defer os.release_log_lock(l);

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
