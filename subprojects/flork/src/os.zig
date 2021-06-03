/// Submodules
pub const lib = @import("lib/lib.zig");
pub const memory = @import("memory/memory.zig");
pub const thread = @import("thread/thread.zig");
pub const platform = @import("platform/platform.zig");
pub const drivers = @import("drivers/drivers.zig");
pub const kernel = @import("kernel/kernel.zig");
pub const kepler = @import("kepler/kepler.zig");

/// OS module itself
pub const log = kernel.logger.log;
pub const hexdump = kernel.logger.hexdump;
pub const hexdump_obj = kernel.logger.hexdump_obj;
pub const vital = kernel.vital.vital;
pub const panic = kernel.panic.panic;

pub const get_log_lock = kernel.logger.get_log_lock;
pub const release_log_lock = kernel.logger.release_log_lock;
