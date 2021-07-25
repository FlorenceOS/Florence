usingnamespace @import("root").preamble;

const paging = os.memory.paging;
const RangeAlloc = os.memory.range_alloc.RangeAlloc;
const DebugAlloc = os.memory.debug_alloc.DebugAlloc;

/// Range allocator for nonbacked memory
pub var nonbacked_alloc = RangeAlloc{};

extern const __kernel_begin: u8;

pub fn init(phys_high: usize) !void {
    os.log("Initializing vmm with base 0x{X}\n", .{phys_high});
    _ = try nonbacked_alloc.addRange(.{
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
