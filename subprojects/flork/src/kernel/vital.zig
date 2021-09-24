usingnamespace @import("root").preamble;

const log = lib.output.log.scoped(.{
    .prefix = "VITAL FAIL",
    .filter = null,
}).write;

pub fn vital(val: anytype, context: []const u8) @TypeOf(val catch unreachable) {
    return val catch |err| {
        log(null, "Fatal Error: {e}, while: {s}", .{ err, context });
        std.builtin.panic("Fatal error", @errorReturnTrace());
    };
}
