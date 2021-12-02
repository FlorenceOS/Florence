const os = @import("root").os;

const log = @import("lib").output.log.scoped(.{
    .prefix = "kernel/vital",
    .filter = null,
}).write;

pub fn vital(val: anytype, context: []const u8) @TypeOf(val catch unreachable) {
    return val catch |err| {
        log(null, "Fatal Error: {e}, while: {s}", .{ err, context });
        @import("std").builtin.panic("Fatal error", @errorReturnTrace());
    };
}
