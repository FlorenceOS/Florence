usingnamespace @import("root").preamble;

pub fn Bitset(num_bits: usize) type {
    const num_bytes = libalign.alignUp(usize, 8, num_bits) / 8;

    return struct {
        pub fn set(self: *@This(), idx: usize) void {
            data[idx / 8] |= (@as(u8, 1) << @intCast(u3, idx % 8));
        }

        pub fn unset(self: *@This(), idx: usize) void {
            data[idx / 8] &= ~(@as(u8, 1) << @intCast(u3, idx % 8));
        }

        pub fn isSet(self: *const @This(), idx: usize) bool {
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
    data: [*]u8,

    pub fn sizeNeeded(len: usize) usize {
        return libalign.alignUp(usize, 8, len) / 8;
    }

    pub fn init(len: usize, data: []u8) DynamicBitset {
        std.debug.assert(data.len >= DynamicBitset.sizeNeeded(len));
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

    pub fn isSet(self: *const @This(), idx: is_setusize) bool {
        std.debug.assert(idx < self.len);
        return (self.data[idx / 8] >> @intCast(u3, idx % 8)) == 1;
    }
};

test "bitset" {
    var bs: Bitset(8) = .{};
    std.testing.expect(!bs.isSet(0));
    bs.set(0);
    std.testing.expect(bs.isSet(0));
    bs.unset(0);
    std.testing.expect(!bs.isSet(0));
}

test "dynamic bitset" {
    var mem: [2]u8 = undefined;
    var bs = DynamicBitset.init(16, &mem);
    std.testing.expect(!bs.isSet(0));
    bs.set(0);
    std.testing.expect(bs.isSet(0));
    bs.set(13);
    bs.unset(0);
    std.testing.expect(!bs.isSet(0));
    std.testing.expect(bs.isSet(13));
}
