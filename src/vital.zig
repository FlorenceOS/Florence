const log = @import("logger.zig").log;

pub fn vital(val: anytype, context: []const u8) @TypeOf(val catch unreachable) {
  return val catch |err| {
    log("Fatal Error: {}, while: {}\n", .{@errorName(err), context});
    @panic("Fatal error");
  };
}
