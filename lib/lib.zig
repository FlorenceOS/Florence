/// Various containers & algorithms
pub const containers = struct {
    /// Atomic queues
    pub const atomic_queue = @import("atomic_queue");

    /// Handle table.
    pub const handle_table = @import("handle_table");

    /// Non-atomic queues
    pub const queue = @import("queue");

    /// Red-black tree
    pub const rbtree = @import("rbtree");

    // pub const refcounted = @import("refcounted");
};

/// File format parsers
pub const format = struct {
    pub const tar = @import("tar");
};

/// Graphics and drawing library
pub const graphics = struct {
    pub const color = @import("color");
    pub const font_renderer = @import("font_renderer");
    pub const glyph_printer = @import("glyph_printer");
    pub const image_region = @import("image_region");
    pub const pixel_format = @import("pixel_format");
    pub const scrolling_region = @import("scrolling_region");
    pub const single_buffer = @import("single_buffer");
};

/// Input libraries
pub const input = struct {
    /// Keyboard input engine
    pub const keyboard = @import("keyboard");
};

/// Memory management lirbaries
pub const memory = struct {
    /// Ranges allocator
    pub const range_alloc = @import("range_alloc");
};

/// Output libraries
pub const output = struct {
    pub const fmt = @import("fmt");
    pub const log = @import("log");
};

/// Various utilities
pub const util = struct {
    /// Bitfields library
    pub const bitfields = @import("bitfields");

    /// Bitsets library
    pub const bitset = @import("bitset");

    /// Callback library
    pub const callback = @import("callback");

    /// Alignment library
    pub const libalign = @import("libalign");

    /// Helpers to manipulate pointers
    pub const pointers = @import("pointers");

    /// Comptime ranges library
    pub const range = @import("range");

    /// Source querying library
    pub const source = @import("source");
};
