usingnamespace @import("root").preamble;

pub fn range(comptime num: usize) [num]comptime_int {
    var ret = [_]comptime_int{0} ** num;
    for (ret) |*v, ind| {
        v.* = ind;
    }
    return ret;
}

pub fn rangeReverse(comptime num: usize) [num]comptime_int {
    var ret = [_]comptime_int{0} ** num;
    for (ret) |*v, ind| {
        v.* = num - ind - 1;
    }
    return ret;
}

test "range" {
    var sum: u64 = 0;

    inline for (range(5)) |v| {
        sum += v;
    }

    std.testing.expect(sum == 1 + 2 + 3 + 4);

    inline for (range(5)) |v, ind| {
        switch (ind) {
            0...4 => std.testing.expect(v == ind),
            else => unreachable,
        }
    }
}

test "rangeReverse" {
    var sum: u64 = 0;

    inline for (rangeReverse(5)) |v| {
        sum += v;
    }

    std.testing.expect(sum == 1 + 2 + 3 + 4);

    inline for (rangeReverse(5)) |v, ind| {
        switch (ind) {
            0...4 => std.testing.expect(v == 5 - ind - 1),
            else => unreachable,
        }
    }
}
