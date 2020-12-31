const libalign = @import("libalign.zig");
const expect = @import("std").testing.expect;

pub fn Bitset(num_bits: usize) type {
    const num_bytes = libalign.align_up(usize, 8, num_bits) / 8;

    return struct {
        pub fn set(self: *@This(), idx: usize) void {
            data[idx / 8] |= (@as(u8, 1) << @intCast(u3, idx % 8));
        }

        pub fn unset(self: *@This(), idx: usize) void {
            data[idx / 8] &= ~(@as(u8, 1) << @intCast(u3, idx % 8));
        }

        pub fn is_set(self: *const @This(), idx: usize) bool {
            return (data[idx / 8] >> @intCast(u3, idx % 8)) == 1;
        }

        pub fn size(self: *const @This()) usize {
            return num_bits;
        }

        var data = [_]u8{0} ** num_bytes;
    };
}

const DynamicBitset = struct {
    len: usize,
    data: []u8,

    pub fn size_needed(len: usize) usize {
        return @divCeil(len, 8);
    }

    pub fn init(len: usize, data: []u8) DynamicBitset {
        for (data) |*cell| {
            cell.* = 0;
        }
        return .{ .len = len, .data = data };
    }

    pub fn set(self: *@This(), idx: usize) void {
        self.data[idx / 8] |= (@as(u8, 1) << @intCast(u3, idx % 8));
    }

    pub fn unset(self: *@This(), idx: usize) void {
        self.data[idx / 8] &= ~(@as(u8, 1) << @intCast(u3, idx % 8));
    }

    pub fn is_set(self: *const @This(), idx: usize) bool {
        return (self.data[idx / 8] >> @intCast(u3, idx % 8)) == 1;
    }
};

test "bitset" {
    var bs: Bitset(8) = .{};
    expect(!bs.is_set(0));
    bs.set(0);
    expect(bs.is_set(0));
    bs.unset(0);
    expect(!bs.is_set(0));
}

test "dynamic bitset" {
    var mem: [2]u8 = undefined;
    var bs: DynamicBitset = DynamicBitset.init(4, &mem);
    expect(!bs.is_set(0));
    bs.set(0);
    expect(bs.is_set(0));
    bs.set(13);
    bs.unset(0);
    expect(!bs.is_set(0));
    expect(bs.is_set(13));
}
