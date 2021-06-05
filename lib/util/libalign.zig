usingnamespace @import("root").preamble;

pub fn alignDown(comptime t: type, alignment: t, value: t) t {
    return value - (value % alignment);
}

pub fn alignUp(comptime t: type, alignment: t, value: t) t {
    return alignDown(t, alignment, value + alignment - 1);
}

pub fn isAligned(comptime t: type, alignment: t, value: t) bool {
    return alignDown(t, alignment, value) == value;
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
