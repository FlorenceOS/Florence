const os = @import("root").os;

pub fn vital(val: anytype, context: []const u8) @TypeOf(val catch unreachable) {
    return val catch |err| {
        os.log("Fatal Error: {s}, while: {s}\n", .{ @errorName(err), context });
        @panic("Fatal error");
    };
}
