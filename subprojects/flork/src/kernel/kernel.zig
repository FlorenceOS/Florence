const os = @import("root").os;
const std = @import("std");

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

pub const objects = @import("objects.zig");

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

const ImageRegion = @import("lib").graphics.image_region.ImageRegion;
const BufferSwitcher = @import("lib").graphics.buffer_switcher.BufferSwitcher(os.thread.Mutex);

var has_proper_framebuffer = false;
pub var klog_viewer: BufferSwitcher = undefined;
var swap_semaphore = os.thread.Semaphore{.available = 0};
const klog_buffer = klog_viewer.primary.region();

pub fn bootFramebuffer(fb: ?*ImageRegion) void {
    std.debug.assert(!has_proper_framebuffer);

    if(fb) |f| {
        os.drivers.output.vesa_log.use(f);

        klog_viewer = os.vital(
            BufferSwitcher.init(f, os.memory.pmm.physHeap()),
            "Allocating buffer switcher",
        );

        os.drivers.output.vesa_log.use(klog_buffer);
    } else {
        os.drivers.output.vga_log.register();
    }
}

pub fn addFramebuffer(fb: *ImageRegion) void {
    if(has_proper_framebuffer) {
        // Just ignore it for now
        return;
    }

    os.drivers.output.vesa_log.use(fb);

    os.vital(
        klog_viewer.retarget(fb, os.memory.pmm.physHeap()),
        "Retargetting klog viewer",
    );

    has_proper_framebuffer = true;
    os.drivers.output.vesa_log.use(klog_buffer);
}

pub fn klogViewerSwap() void {
    swap_semaphore.release(1);
}

fn klogViewerSwapper() void {
    while(true) {
        swap_semaphore.acquire(1);
        klog_viewer.swap();
    }
}

pub fn kmain() noreturn {
    objects.launchPrintTask();
    os.thread.scheduler.spawnTask("Klog switcher task", klogViewerSwapper, .{ }) catch @panic("Could not launch klog switcher");

    if (@import("config").kernel.kepler.run_tests) {
        os.kepler.tests.run();
    }

    var proc: process.Process = undefined;
    os.vital(proc.init("init"), "init proc launch");

    os.thread.scheduler.exitTask();
}
