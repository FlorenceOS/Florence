/// MMIO serial driver
pub const mmio_serial = @import("mmio_serial.zig");

// A simple display interface that only provides a single mode from a framebuffer
pub const single_mode_display = @import("single_mode_display.zig");

/// VESA display output driver
pub const vesa_log = @import("vesa_log.zig");

/// VGA text mode output driver
pub const vga_log = @import("vga_log.zig");

/// Graphics/video interface structs
pub const video = @import("video.zig");
