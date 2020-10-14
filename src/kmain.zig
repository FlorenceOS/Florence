const log = @import("logger.zig").log;
const arch = @import("builtin").arch;
const platform = @import("platform.zig");
const scheduler = @import("scheduler.zig");
const vital = @import("vital.zig").vital;

const acpi = @import("platform/acpi.zig");
const pci = @import("platform/pci.zig");

pub fn kmain() noreturn {
  log("Hello, kmain!\n", .{});

  vital(platform.platform_init(), "calling platform_init");
  vital(acpi.init_acpi(), "calling init_acpi");
  vital(pci.init_pci(), "calling init_pci");

  scheduler.exit_task();
}
