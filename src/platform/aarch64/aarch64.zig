const std = @import("std");
const assert = std.debug.assert;

pub const page_sizes =
  [_]u64 {
    0x4000,
  };


// All mapping_ bits are ignored when it is a table,
// all table_   bits are ignored when it is a mapping.
// PXN is XN for EL3
pub const page_table_entry = packed struct {
  valid: u1,
  walk: u1,
  mapping_memory_attribute_index: u3, // 0 for device, 1 for normal
  mapping_nonsecure: u1,
  mapping_access: u2, // [2:1]=0 for RW, 2 for RO
  mapping_shareability: u2,
  mapping_accessed: u1,
  mapping_nonGlobal: u1,
  physaddr_bits: u36,
  zeroes: u4,
  mapping_hint: u1,
  mapping_pxn: u1,
  mapping_xn: u1,
  ignored: u4,
  table_pxn: u1,
};

comptime {
  assert(@bitSizeOf(page_table_entry) == 64);
}

pub fn platform_init() !void {
  try @import("../devicetree.zig").parse_dt(null);
}

pub fn debugputch(val: u8) void {
  @intToPtr(*volatile u32, 0x9000000).* = val;
}
