const assert = @import("std").debug.assert;

pub fn range(comptime num: usize) [num]comptime_int {
    var ret = [_]comptime_int{0} ** num;
    for (ret) |*v, ind| {
        v.* = ind;
    }
    return ret;
}

test "range" {
    var sum: u64 = 0;
    inline for (range(5)) |v| {
        sum += v;
    }
    assert(sum == 1 + 2 + 3 + 4);

    inline for (range(5)) |v, ind| {
        switch (ind) {
            0...4 => assert(v == ind),
            else => unreachable,
        }
    }
}

pub fn range_reverse(comptime num: usize) [num]comptime_int {
    var ret = [_]comptime_int{0} ** num;
    for (ret) |*v, ind| {
        v.* = num - ind - 1;
    }
    return ret;
}

test "range_reverse" {
    var sum: u64 = 0;
    inline for (range_reverse(5)) |v| {
        sum += v;
    }
    assert(sum == 1 + 2 + 3 + 4);

    inline for (range_reverse(5)) |v, ind| {
        switch (ind) {
            0...4 => assert(v == 5 - ind - 1),
            else => unreachable,
        }
    }
}
