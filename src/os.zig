// Submodules
pub const lib      = @import("lib/lib.zig");
pub const memory   = @import("memory/memory.zig");
pub const thread   = @import("thread/thread.zig");
pub const platform = @import("platform/platform.zig");
pub const drivers  = @import("drivers/drivers.zig");
pub const kernel   = @import("kernel/kernel.zig");
pub const external = @import("external/external.zig");
pub const userspace = @import("userspace/userspace.zig");

// OS module itself
pub const log         = lib.logger.log;
pub const hexdump     = lib.logger.hexdump;
pub const hexdump_obj = lib.logger.hexdump_obj;
pub const vital       = lib.vital.vital;
pub const panic       = lib.panic.panic;
