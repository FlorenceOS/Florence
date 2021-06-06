/// Paging functions
pub const paging = @import("paging.zig");

/// Virtual memory management
pub const vmm = @import("vmm.zig");

/// Physical memory management
pub const pmm = @import("pmm.zig");

/// (Non)paged memory allocator
pub const range_alloc = @import("range_alloc.zig");
