usingnamespace @import("root").preamble;

// PTEs have to be a tagged union of this enum type
pub const PTEType = enum {
    Mapping, Table, Empty
};
