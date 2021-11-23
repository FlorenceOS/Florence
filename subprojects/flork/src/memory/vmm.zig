usingnamespace @import("root").preamble;

const std = @import("std");
const lib = @import("lib");

const log = lib.output.log.scoped(.{
    .prefix = "memory/vmm",
    .filter = .info,
}).write;

const paging = os.memory.paging;
const RangeAllocator = lib.memory.range_alloc.RangeAllocator;

/// Range allocator for nonbacked memory
pub var nonbacked_alloc = RangeAllocator(os.thread.Mutex).init(os.memory.pmm.phys_heap);

extern const __kernel_begin: u8;

pub fn init(phys_high: usize) !void {
    log(.debug, "Initializing vmm with base 0x{X}", .{phys_high});
    try nonbacked_alloc.ra.giveRange(.{
        .base = phys_high,
        .size = @ptrToInt(&__kernel_begin) - phys_high,
    });
}

/// The virtual memory is _NOT_ backed by physical pages.
/// If you dereference this memory, you _WILL_ get a page
/// fault. The pointers into this memory cannot be dereferenced
/// before mapping the memory to some physical memory.
pub fn nonbacked() *std.mem.Allocator {
    return &nonbacked_alloc.allocator;
}
