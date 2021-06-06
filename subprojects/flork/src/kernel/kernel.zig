usingnamespace @import("root").preamble;
const arch = std.builtin.arch;

/// Debugging helpers
pub const debug = @import("debug.zig");

/// Logging facilities
pub const logger = @import("logger.zig");

/// Panic handler
pub const panic = @import("panic.zig");

/// vital() function
pub const vital = @import("vital.zig");

/// Lightweight ACPI interpreter
pub const lai = @cImport({
    @cInclude("lai/core.h");
    @cInclude("lai/error.h");
    @cInclude("lai/host.h");
    @cInclude("lai/drivers/ec.h");
    @cInclude("lai/drivers/timer.h");
    @cInclude("lai/helpers/pc-bios.h");
    @cInclude("lai/helpers/pci.h");
    @cInclude("lai/helpers/pm.h");
    @cInclude("lai/helpers/resource.h");
    @cInclude("lai/helpers/sci.h");
});

pub fn kmain() noreturn {
    os.log("Hello, kmain!\n", .{});
    os.vital(os.kepler.tests.run_tests(), "Kepler tests terminated with error");

    os.thread.scheduler.exit_task();
}
