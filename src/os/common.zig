const std = @import("std");
const debug = @import("../debug.zig");

pub const heap = .{
  .page_allocator = debug.debug_allocator,
};
