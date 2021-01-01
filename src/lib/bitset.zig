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

const DynamicBitsetInitError = error{NotEnoughMemory};

const DynamicBitset = struct {
    len: usize,
    data: [*]u8,

    pub fn size_needed(len: usize) usize {
        return libalign.align_up(usize, 8, len) / 8;
    }

    pub fn init(len: usize, data: []u8) DynamicBitsetInitError!DynamicBitset {
        if (data.len < DynamicBitset.size_needed(len)) {
            return error.NotEnoughMemory;
        }
        for (data) |*cell| {
            cell.* = 0;
        }
        return DynamicBitset{ .len = len, .data = data.ptr };
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

test "dynamic bitset init error" {
    var mem: [2]u8 = undefined;
    var bs: DynamicBitsetInitError!DynamicBitset = DynamicBitset.init(36, &mem) catch |_| return;
    unreachable;
}

test "dynamic bitset" {
    var mem: [2]u8 = undefined;
    var bs: DynamicBitset = try DynamicBitset.init(4, &mem);
    expect(!bs.is_set(0));
    bs.set(0);
    expect(bs.is_set(0));
    bs.set(13);
    bs.unset(0);
    expect(!bs.is_set(0));
    expect(bs.is_set(13));
}
