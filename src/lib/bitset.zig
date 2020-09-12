const libalign = @import("align.zig");

pub fn bitset(num_bits: usize) type {
  const num_bytes = libalign.align_up(usize, 8, num_bits)/8;

  return struct {
    pub fn set(self: *@This(), idx: usize) void {
      data[idx/8] |= (@as(u8, 1) << @intCast(u3, idx % 8));
    }

    pub fn unset(self: *@This(), idx: usize) void {
      data[idx/8] &= ~(@as(u8, 1) << @intCast(u3, idx % 8));
    }

    pub fn is_set(self: *const @This(), idx: usize) bool {
      return (data[idx/8] >> @intCast(u3, idx % 8)) == 1; 
    }

    pub fn size(self: *const @This()) usize {
      return num_bits;
    }

    var data = [_]u8{0}**num_bytes;
  };
}

test "bitset" {
  const expect = @import("std").testing.expect;

  var bs: bitset(8) = .{};
  expect(!bs.is_set(0));
  bs.set(0);
  expect(bs.is_set(0));
  bs.unset(0);
  expect(!bs.is_set(0));
}
