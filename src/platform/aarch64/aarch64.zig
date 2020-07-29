pub const page_sizes =
  [_]u64 {
    0x4000,
  };

pub fn platform_init() !void {
  try @import("../devicetree.zig").parse_dt(null);
}

pub fn debugputch(val: u8) void {
  @intToPtr(*volatile u8, 0x9000000).* = val;
}
