const log = @import("logger.zig").log;
const arch = @import("builtin").arch;
const platform = @import("platform.zig");

pub fn kmain() !void {
  log("Hello kernel!\n", .{});
}
