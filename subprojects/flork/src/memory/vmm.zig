const os = @import("root").os;
const std = @import("std");
const lib = @import("lib");

const log = lib.output.log.scoped(.{
    .prefix = "memory/vmm",
    .filter = .info,
}).write;

const paging = os.memory.paging;
const RangeAlloc = lib.memory.range_alloc.RangeAlloc;

var mtx: os.thread.Mutex = .{};

/// Range allocator for nonbacked memory
var nonbacked = RangeAlloc{
    .backing_allocator = os.memory.pmm.physHeap(),
};

extern const __kernel_begin: u8;

pub fn init(phys_high: usize) !void {
    log(.debug, "Initializing vmm with base 0x{X}", .{phys_high});
    try nonbacked.giveRange(phys_high, @ptrToInt(&__kernel_begin) - phys_high);
}

pub fn allocNonbacked(len: usize, ptr_align: usize, len_align: usize) !usize {
    mtx.lock();
    defer mtx.unlock();

    return nonbacked.allocateAnywhere(len, ptr_align, len_align);
}

pub fn freeNonbacked(virt: usize, len: usize) !void {
    mtx.lock();
    defer mtx.unlock();

    try nonbacked.giveRange(virt, len);
}
