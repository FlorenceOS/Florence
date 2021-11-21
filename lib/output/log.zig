const libfmt = @import("fmt");
const std = @import("std");

const Mutex = @import("root").os.thread.Mutex;

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
        return "[" ++ tag.prefix ++ "] " ++ @tagName(log_level.?) ++ ": " ++ fmt;
    return "[" ++ tag.prefix ++ "] " ++ fmt;
}

inline fn writeImpl(comptime tag: anytype, comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype) void {
    if (comptime enabled(tag, log_level)) {
        const l = getLock();
        defer l.release();
        libfmt.doFmt(comptime taggedLogFmt(tag, log_level, fmt), args);
    }
}

inline fn startImpl(comptime tag: anytype, comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype) held_t(tag, log_level) {
    if (comptime enabled(tag, log_level)) {
        const l = getLock();
        libfmt.doFmtNoEndl(comptime taggedLogFmt(tag, log_level, fmt), args);
        return l;
    }
}

inline fn contImpl(comptime tag: anytype, comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype, _: held_t(tag, log_level)) void {
    if (comptime enabled(tag, log_level)) {
        libfmt.doFmtNoEndl(fmt, args);
    }
}

inline fn finishImpl(comptime tag: anytype, comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype, l: held_t(tag, log_level)) void {
    if (comptime enabled(tag, log_level)) {
        libfmt.doFmt(fmt, args);
        l.release();
    }
}

pub fn scoped(comptime tag: anytype) type {
    return struct {
        pub const write = struct {
            pub inline fn f(comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype) void {
                writeImpl(tag, log_level, fmt, args);
            }
        }.f;

        pub const start = struct {
            pub inline fn f(comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype) held_t(tag, log_level) {
                return startImpl(tag, log_level, fmt, args);
            }
        }.f;

        pub const cont = struct {
            pub inline fn f(comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype, m: held_t(tag, log_level)) void {
                return contImpl(tag, log_level, fmt, args, m);
            }
        }.f;

        pub const finish = struct {
            pub inline fn f(comptime log_level: ?std.log.Level, comptime fmt: []const u8, args: anytype, m: held_t(tag, log_level)) void {
                return finishImpl(tag, log_level, fmt, args, m);
            }
        }.f;
    };
}
