/// Various containers & algorithms
pub const containers = struct {
    /// Atomic queues
    pub const atomic_queue = @import("containers/atomic_queue.zig");

    /// Handle table.
    pub const handle_table = @import("containers/handle_table");

    /// Non-atomic queues
    pub const queue = @import("containers/queue.zig");

    /// Red-black tree
    pub const rbtree = @import("containers/rbtree.zig");

    // pub const refcounted = @import("containers/refcounted.zig");
};

/// File format parsers
pub const format = struct {
    pub const tar = @import("format/tar.zig");
};

/// Graphics and drawing library
pub const graphics = struct {
    pub const color = @import("graphics/color.zig");
    pub const font_renderer = @import("graphics/font_renderer.zig");
    pub const glyph_printer = @import("graphics/glyph_printer.zig");
    pub const image_region = @import("graphics/image_region.zig");
    pub const pixel_format = @import("graphics/pixel_format.zig");
    pub const scrolling_region = @import("graphics/scrolling_region.zig");
    pub const single_buffer = @import("graphics/single_buffer.zig");
};

/// Input libraries
pub const input = struct {
    /// Keyboard input engine
    pub const keyboard = @import("input/keyboard/keyboard.zig");
};

/// Memory management lirbaries
pub const memory = struct {
    /// Ranges allocator
    pub const range_alloc = @import("memory/range_alloc.zig");
};

/// Output libraries
pub const output = struct {
    pub const fmt = @import("output/fmt.zig");
    pub const log = @import("output/log.zig");
};

/// Various utilities
pub const util = struct {
    /// Bitfields library
    pub const bitfields = @import("util/bitfields.zig");

    /// Bitsets library
    pub const bitset = @import("util/bitset.zig");

    /// Callback library
    pub const callback = @import("util/callback.zig");

    /// Alignment library
    pub const libalign = @import("util/libalign.zig");

    /// Helpers to manipulate pointers
    pub const pointers = @import("util/pointers.zig");

    /// Comptime ranges library
    pub const range = @import("util/range.zig");

    /// Source querying library
    pub const source = @import("util/source.zig");
};
