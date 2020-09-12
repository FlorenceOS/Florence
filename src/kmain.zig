const log = @import("logger.zig").log;
const arch = @import("builtin").arch;
const platform = @import("platform.zig");

const acpi = @import("platform/acpi.zig");

pub fn kmain() noreturn {
  log("Hello, kmain!\n", .{});
  acpi: {
    log("Initializing ACPI!\n", .{});
    acpi.init_acpi() catch |err| {
      log("ACPI init failed: {}\n", .{@errorName(err)});
      break :acpi;
    };
    log("ACPI init finished!\n", .{});
  }
  while(true) {
    asm volatile("pause");
  }
}
