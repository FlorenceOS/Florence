const os = @import("root").os;
const arch = @import("builtin").arch;
const pci = os.platform.pci;

pub fn kmain() noreturn {
  os.log("Hello, kmain!\n", .{});

  var i: u64 = 0;
  while(true) {
    os.log("Hello, iteration {}\n", .{i});
    i += 1;
    os.thread.scheduler.yield();
  }

  os.thread.scheduler.exit_task();
}
