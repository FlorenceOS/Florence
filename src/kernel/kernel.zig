const os = @import("root").os;
const arch = @import("builtin").arch;
const pci = os.platform.pci;

pub fn kmain() noreturn {
  os.log("Hello, kmain!\n", .{});

  os.thread.scheduler.exit_task();
}
