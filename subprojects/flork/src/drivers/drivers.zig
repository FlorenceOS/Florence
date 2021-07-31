/// Block device drivers
pub const block = @import("block/block.zig");

/// GPU drivers
pub const gpu = @import("gpu/gpu.zig");

/// Misc device drivers
pub const misc = @import("misc/misc.zig");

/// Networking related drivers
pub const net = @import("net/net.zig");

/// Output device drivers
pub const output = @import("output/output.zig");

/// USB controller and device drivers
pub const usb = @import("usb/usb.zig");
