const os = @import("root").os;
const arch = @import("builtin").arch;

pub fn kmain() noreturn {
  os.log("Hello, kmain!\n", .{});

  os.vital(os.platform.platform_init(), "calling platform_init");

  os.thread.scheduler.exit_task();
}
