const std = @import("std");

pub fn packed_int(comptime num_bits: usize, comptime result_type: type, comptime shamt: usize) type {
  const storage_type = std.meta.Int(.unsigned, num_bits);
  return packed struct {
    raw: storage_type,

    pub fn get(self: *const @This()) result_type {
      return @as(result_type, self.raw) << shamt;
    }

    pub fn init(val: result_type) @This() {
      var result: @This() = undefined;
      result.write(val);
      return result;
    }

    pub fn write(self: *@This(), val: result_type) void {
      // Assert that only active bits are used
      std.debug.assert(val & (~((@as(result_type, 1) << num_bits) - 1) << shamt) == 0);
      self.raw = @intCast(storage_type, val >> shamt);
    }
  };
}

test "packed_int" {
  const thing = packed_int(4, u64, 10);
  std.debug.assert(@bitSizeOf(thing) == 4);

  var a = thing.init(2048);
  std.testing.expect(a.get() == 2048);

  a.write(4096);
  std.testing.expect(a.get() == 4096);

  const b = thing.init(2048);
  std.testing.expect(b.get() == 2048);
}
