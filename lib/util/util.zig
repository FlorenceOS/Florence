/// Bitfields library
pub const bitfields = @import("bitfields.zig");

/// Bitsets library
pub const bitset = @import("bitset.zig");

/// Callback library
pub const callback = @import("callback.zig");

/// Alignment library
pub const libalign = @import("libalign.zig");

/// Comptime ranges library
pub const range = @import("range.zig");

/// Source querying library
pub const source = @import("source.zig");

/// Helpers to manipulate pointers
pub const pointers = @import("pointers.zig");

pub fn isRuntime() bool {
    var b = true;
    const v = if (b) @as(u8, 0) else @as(u32, 0);
    return @TypeOf(v) == u32;
}
