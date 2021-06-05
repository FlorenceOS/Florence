usingnamespace @import("root").preamble;

pub fn getIndex(ptr: anytype, slice: []@TypeOf(ptr.*)) usize {
    return (@ptrToInt(ptr) - @ptrToInt(slice.ptr)) / @sizeOf(@TypeOf(ptr.*));
}
