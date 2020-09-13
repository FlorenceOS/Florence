const log = @import("logger.zig").log;
const arch = @import("builtin").arch;
const platform = @import("platform.zig");

const acpi = @import("platform/acpi.zig");
const pci = @import("platform/pci.zig");

const arch = @import("builtin").arch;

pub fn kmain() noreturn {
  log("Hello, kmain!\n", .{});

  acpi.init_acpi() catch |err| {
    log("ACPI init failed: {}\n", .{@errorName(err)});
  };

  pci.init_pci() catch |err| {
    log("PCI init failed: {}\n", .{@errorName(err)});
  };

  while(true) {
    if(arch == .x86_64) {
      asm volatile("pause");
    }
  }
}
