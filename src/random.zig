const std = @import("std");

pub const rand = std.rand.Random {
  .fillFn = fill,
};
