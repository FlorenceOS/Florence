/// Submodules
pub const memory = @import("memory/memory.zig");
pub const thread = @import("thread/thread.zig");
pub const platform = @import("platform/platform.zig");
pub const drivers = @import("drivers/drivers.zig");
pub const kernel = @import("kernel/kernel.zig");
pub const kepler = @import("kepler/kepler.zig");

/// OS module itself
pub const log = kernel.logger.log;
pub const hexdump = kernel.logger.hexdump;
pub const hexdumpObj = kernel.logger.hexdumpObj;
pub const vital = kernel.vital.vital;
pub const panic = kernel.panic.panic;

pub const getLogLock = kernel.logger.getLogLock;
pub const releaseLogLock = kernel.logger.releaseLogLock;
