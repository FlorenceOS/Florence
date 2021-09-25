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

/// Userspace processes
pub const process = @import("process.zig");

/// Copernicus userspace library
pub const copernicus = @import("copernicus.zig");

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
    if (config.kernel.kepler.run_tests) {
        os.kepler.tests.run();
    }

    var proc: process.Process = undefined;
    os.vital(proc.init("init"), "init proc launch");

    os.thread.scheduler.exitTask();
}
