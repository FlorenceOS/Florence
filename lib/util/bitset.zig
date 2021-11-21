const std = @import("std");

pub fn Bitset(num_bits: usize) type {
    const num_bytes = @divTrunc(num_bits + 7, 8);

    return struct {
        pub fn set(self: *@This(), idx: usize) void {
            self.data[idx / 8] |= (@as(u8, 1) << @intCast(u3, idx % 8));
        }

        pub fn unset(self: *@This(), idx: usize) void {
            self.data[idx / 8] &= ~(@as(u8, 1) << @intCast(u3, idx % 8));
        }

        pub fn isSet(self: *const @This(), idx: usize) bool {
            return (self.data[idx / 8] >> @intCast(u3, idx % 8)) == 1;
        }

        pub fn size(_: *const @This()) usize {
            return num_bits;
        }

        data: [num_bytes]u8 = [_]u8{0} ** num_bytes,
    };
}

const DynamicBitset = struct {
    len: usize,
    data: [*]u8,

    pub fn bytesNeeded(len: usize) usize {
        return @divTrunc(len + 7, 8);
    }

    pub fn init(len: usize, data: []u8) DynamicBitset {
        std.debug.assert(data.len >= DynamicBitset.bytesNeeded(len));
        for (data) |*cell| {
            cell.* = 0;
        }
        return DynamicBitset{ .len = len, .data = data.ptr };
    }

    pub fn set(self: *@This(), idx: usize) void {
        std.debug.assert(idx < self.len);
        self.data[idx / 8] |= (@as(u8, 1) << @intCast(u3, idx % 8));
    }

    pub fn unset(self: *@This(), idx: usize) void {
        std.debug.assert(idx < self.len);
        self.data[idx / 8] &= ~(@as(u8, 1) << @intCast(u3, idx % 8));
    }

    pub fn isSet(self: *const @This(), idx: usize) bool {
        std.debug.assert(idx < self.len);
        return (self.data[idx / 8] >> @intCast(u3, idx % 8)) == 1;
    }
};

test "bitset" {
    var bs: Bitset(8) = .{};
    try std.testing.expect(!bs.isSet(0));
    bs.set(0);
    try std.testing.expect(bs.isSet(0));
    bs.unset(0);
    try std.testing.expect(!bs.isSet(0));
}

test "dynamic bitset" {
    var mem: [2]u8 = undefined;
    var bs = DynamicBitset.init(16, &mem);
    try std.testing.expect(!bs.isSet(0));
    bs.set(0);
    try std.testing.expect(bs.isSet(0));
    bs.set(13);
    bs.unset(0);
    try std.testing.expect(!bs.isSet(0));
    try std.testing.expect(bs.isSet(13));
}
