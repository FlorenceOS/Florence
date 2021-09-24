usingnamespace @import("root").preamble;

const fmt_lib = @import("fmt.zig");

const Mutex = os.thread.Mutex;

var mutex = Mutex{};
noinline fn getLock() Mutex.Held {
    return mutex.acquire();
}

const enable_all_logging = false;

fn enabled(comptime tag: anytype, comptime log_level: ?std.log.Level) bool {
    if (enable_all_logging) return true;
    const filter: ?std.log.Level = tag.filter;
    if (filter) |f| {
        if (log_level) |l| {
            return @enumToInt(l) < @enumToInt(f);
        }
    }
    return true;
}

fn held_t(comptime tag: anytype, comptime log_level: ?std.log.Level) type {
    return if (enabled(tag, log_level)) Mutex.Held else void;
}

fn taggedLogFmt(comptime tag: anytype, comptime log_level: ?std.log.Level, comptime fmt: []const u8) []const u8 {
    if (log_level != null)
        return "[" ++ tag.prefix ++ "]: " ++ @tagName(log_level.?) ++ ": " ++ fmt;
    return "[" ++ tag.prefix ++ "]: " ++ fmt;
}

fn writeImpl(comptime tag: anytype, comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype) callconv(.Inline) void {
    if (comptime enabled(tag, log_level)) {
        const l = getLock();
        defer l.release();
        fmt_lib.doFmt(comptime taggedLogFmt(tag, log_level, fmt), args);
    }
}

fn startImpl(comptime tag: anytype, comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype) callconv(.Inline) held_t(tag, log_level) {
    if (comptime enabled(tag, log_level)) {
        const l = getLock();
        fmt_lib.doFmtNoEndl(comptime taggedLogFmt(tag, log_level, fmt), args);
        return l;
    }
}

fn contImpl(comptime tag: anytype, comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype, _: held_t(tag, log_level)) callconv(.Inline) void {
    if (comptime enabled(tag, log_level)) {
        fmt_lib.doFmtNoEndl(fmt, args);
    }
}

fn finishImpl(comptime tag: anytype, comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype, l: held_t(tag, log_level)) callconv(.Inline) void {
    if (comptime enabled(tag, log_level)) {
        fmt_lib.doFmt(fmt, args);
        l.release();
    }
}

pub fn scoped(comptime tag: anytype) type {
    return struct {
        pub const write = struct {
            pub fn f(comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype) callconv(.Inline) void {
                writeImpl(tag, log_level, fmt, args);
            }
        }.f;

        pub const start = struct {
            pub fn f(comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype) callconv(.Inline) held_t(tag, log_level) {
                return startImpl(tag, log_level, fmt, args);
            }
        }.f;

        pub const cont = struct {
            pub fn f(comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype, m: held_t(tag, log_level)) callconv(.Inline) void {
                return contImpl(tag, log_level, fmt, args, m);
            }
        }.f;

        pub const finish = struct {
            pub fn f(comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype, m: held_t(tag, log_level)) callconv(.Inline) void {
                return finishImpl(tag, log_level, fmt, args, m);
            }
        }.f;
    };
}
