const os = @import("root").os;
const arch = @import("builtin").arch;

pub fn kmain() noreturn {
  os.log("Hello, kmain!\n", .{});
  os.log("Lol!\n", .{});
  os.vital(os.kepler.tests.basic(), "Kepler tests terminated with error");

  os.thread.scheduler.exit_task();
}
