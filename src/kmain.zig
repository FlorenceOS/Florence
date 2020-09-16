const log = @import("logger.zig").log;
const arch = @import("builtin").arch;
const platform = @import("platform.zig");

const acpi = @import("platform/acpi.zig");
const pci = @import("platform/pci.zig");

pub fn kmain() noreturn {
  log("Hello, kmain!\n", .{});

  acpi.init_acpi() catch |err| {
    log("ACPI init failed: {}\n", .{@errorName(err)});
  };

  pci.init_pci() catch |err| {
    log("PCI init failed: {}\n", .{@errorName(err)});
  };

  scheduler.exit_task();
}
