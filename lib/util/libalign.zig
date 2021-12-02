const std = @import("std");

pub fn alignDown(comptime t: type, alignment: t, value: t) t {
    return value - (value % alignment);
}

pub fn alignUp(comptime t: type, alignment: t, value: t) t {
    return alignDown(t, alignment, value + alignment - 1);
}

pub fn isAligned(comptime t: type, alignment: t, value: t) bool {
    return alignDown(t, alignment, value) == value;
}

fn isRuntime() bool {
    var b = true;
    const v = if (b) @as(u8, 0) else @as(u32, 0);
    return @TypeOf(v) == u32;
}

fn sliceAlignCast(comptime t: type, slice: anytype) !(if (std.meta.trait.isConstPtr(@TypeOf(slice.ptr))) []const t else []t) {
    const alignment = @alignOf(t);
    comptime const ptr_type = if (std.meta.trait.isConstPtr(@TypeOf(slice.ptr))) [*]const t else [*]t;
    if (isRuntime() // we can't detect alignment of pointer values at comptime, not that it matters anyways
    and isAligned(usize, alignment, @ptrToInt(slice.ptr)) // base ptr aligned
    and isAligned(usize, alignment, slice.len)) { // length aligned
        return @ptrCast(
            ptr_type,
            @alignCast(alignment, slice.ptr),
        )[0..@divExact(slice.len, alignment)];
    }
    return error.NotAligned;
}

pub fn alignedCopy(comptime t: type, dest: []u8, src: []const u8) void {
    const dest_aligned = sliceAlignCast(t, dest) catch return std.mem.copy(u8, dest, src);
    const src_aligned = sliceAlignCast(t, src) catch return std.mem.copy(u8, dest, src);
    return std.mem.copy(t, dest_aligned, src_aligned);
}

pub fn alignedFill(comptime t: type, dest: []u8, value: u8) void {
    const dest_aligned = sliceAlignCast(t, dest) catch return std.mem.set(u8, dest, value);
    const big_value = @truncate(t, 0x0101010101010101) * @intCast(t, value);
    return std.mem.set(t, dest_aligned, big_value);
}

test "alignDown" {
    std.testing.expect(alignDown(u64, 0x1000, 0x4242) == 0x4000);
    std.testing.expect(alignDown(u64, 0x1000, 0x1000) == 0x1000);
    std.testing.expect(alignDown(u64, 0x1000, 0x1FFF) == 0x1000);
    std.testing.expect(alignDown(u64, 0x1000, 0x2000) == 0x2000);
}

test "alignUp" {
    std.testing.expect(alignUp(u64, 0x1000, 0x4242) == 0x5000);
    std.testing.expect(alignUp(u64, 0x1000, 0x1000) == 0x1000);
    std.testing.expect(alignUp(u64, 0x1000, 0x1001) == 0x2000);
    std.testing.expect(alignUp(u64, 0x1000, 0x2000) == 0x2000);
}

test "isAligned" {
    std.testing.expect(isAligned(u64, 0x1000, 0x1000));
    std.testing.expect(!isAligned(u64, 0x1000, 0x1001));
    std.testing.expect(!isAligned(u64, 0x1000, 0x1FFF));
    std.testing.expect(isAligned(u64, 0x1000, 0x2000));
}
