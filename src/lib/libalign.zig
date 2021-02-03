const assert = @import("std").debug.assert;

pub fn align_down(comptime t: type, alignment: t, value: t) t {
    return value - (value % alignment);
}

test "align_down" {
    assert(align_down(u64, 0x1000, 0x4242) == 0x4000);

    assert(align_down(u64, 0x1000, 0x1000) == 0x1000);
    assert(align_down(u64, 0x1000, 0x1FFF) == 0x1000);
    assert(align_down(u64, 0x1000, 0x2000) == 0x2000);
}

pub fn align_up(comptime t: type, alignment: t, value: t) t {
    return align_down(t, alignment, value + alignment - 1);
}

test "align_up" {
    assert(align_up(u64, 0x1000, 0x4242) == 0x5000);

    assert(align_up(u64, 0x1000, 0x1000) == 0x1000);
    assert(align_up(u64, 0x1000, 0x1001) == 0x2000);
    assert(align_up(u64, 0x1000, 0x2000) == 0x2000);
}

pub fn is_aligned(comptime t: type, alignment: t, value: t) bool {
    return align_down(t, alignment, value) == value;
}

test "is_aligned" {
    assert(is_aligned(u64, 0x1000, 0x1000) == true);
    assert(is_aligned(u64, 0x1000, 0x1001) == false);
    assert(is_aligned(u64, 0x1000, 0x1FFF) == false);
    assert(is_aligned(u64, 0x1000, 0x2000) == true);
}
