usingnamespace @import("root").preamble;

const paging = os.memory.paging;
const RangeAlloc = os.memory.range_alloc.RangeAlloc;
const DebugAlloc = os.memory.debug_alloc.DebugAlloc;
const Mutex = os.thread.Mutex;

/// Describes the lifetime of the memory aquired from an allocator
const Lifetime = enum {
    /// Ephemeral memory won't last for the entire uptime of the kernel,
    /// it can be freed to make it available to the rest of the system.
    Ephemeral,

    /// Eternal memory will remain allocated until system shutdown. It
    /// cannot be freed. Ever.
    Eternal,
};

var sbrk_head: usize = undefined;
var sbrk_mutex = Mutex{};

/// Range allocator for backed memory
var backed_alloc = switch (config.kernel.heap_debug_allocator) {
    true => DebugAlloc,
    false => RangeAlloc,
}{
    .backed = true,
};

var ephemeral_alloc =
    std.heap.GeneralPurposeAllocator(.{
    .thread_safe = true,
    .MutexType = os.thread.Mutex,
}){
    .backing_allocator = &backed_alloc.allocator,
};

/// Range allocator for nonbacked memory
pub var nonbacked_alloc = switch (config.kernel.heap_debug_allocator) {
    true => DebugAlloc,
    false => RangeAlloc,
}{
    .backed = false,
};

pub fn init(phys_high: usize) !void {
    os.log("Initializing vmm with base 0x{X}\n", .{phys_high});
    sbrk_head = phys_high;
}

pub fn sbrkNonbacked(num_bytes: usize) ![]u8 {
    sbrk_mutex.lock();
    defer sbrk_mutex.unlock();

    const ret = sbrk_head;

    sbrk_head += num_bytes;

    return @intToPtr([*]u8, ret)[0..num_bytes];
}

pub fn sbrk(num_bytes: usize) ![]u8 {
    const ret = try sbrkNonbacked(num_bytes);

    try paging.map(.{
        .virt = @ptrToInt(ret.ptr),
        .size = num_bytes,
        .perm = paging.rw(),
        .memtype = .MemoryWriteBack,
    });

    return ret;
}

/// The virtual memory is backed by physical pages.
/// You can dereference these pointers just like in your
/// normal programs
pub fn backed(
    lifetime: Lifetime,
) *std.mem.Allocator {
    switch (lifetime) {
        .Ephemeral => {
            if (comptime (config.kernel.heap_debug_allocator)) {
                return &backed_alloc.allocator;
            }
            return &ephemeral_alloc.allocator;
        },
        .Eternal => return &backed_alloc.allocator,
    }
}

/// The virtual memory is _NOT_ backed by physical pages.
/// If you dereference this memory, you _WILL_ get a page
/// fault. The pointers into this memory cannot be dereferenced
/// before mapping the memory to some physical memory.
pub fn nonbacked() *std.mem.Allocator {
    return &nonbacked_alloc.allocator;
}

export fn laihost_malloc(sz: usize) ?*c_void {
    if (sz == 0) return @intToPtr(*c_void, 0x1000);
    const mem = os.memory.vmm.backed(.Ephemeral).alloc(u8, sz) catch return os.kernel.lai.NULL;
    return @ptrCast(*c_void, mem.ptr);
}

export fn laihost_realloc(ptr: ?*c_void, newsize: usize, oldsize: usize) ?*c_void {
    std.debug.assert((ptr == null) == (oldsize == 0));
    if (oldsize == 0) {
        return laihost_malloc(newsize);
    }
    if (newsize == 0) {
        laihost_free(ptr, oldsize);
        return os.kernel.lai.NULL;
    }
    const ret = laihost_malloc(newsize);
    @memcpy(@ptrCast([*]u8, ret), @ptrCast([*]const u8, ptr), oldsize);
    laihost_free(ptr, oldsize);
    return ret;
}

export fn laihost_free(ptr: ?*c_void, oldsize: usize) void {
    if (ptr == null) return;
    os.memory.vmm.backed(.Ephemeral).free(@ptrCast([*]u8, ptr)[0..oldsize]);
}
