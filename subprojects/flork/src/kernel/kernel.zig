const os = @import("root").os;
const arch = @import("builtin").arch;

pub const debug = @import("debug.zig");
pub const logger = @import("logger.zig");
pub const panic = @import("panic.zig");
pub const vital = @import("vital.zig");

pub fn kmain() noreturn {
  os.log("Hello, kmain!\n", .{});
  os.vital(os.kepler.tests.run_tests(), "Kepler tests terminated with error");

  os.thread.scheduler.exit_task();
}
