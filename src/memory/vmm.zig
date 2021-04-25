const std = @import("std");
const os = @import("root").os;

const paging     = os.memory.paging;
const RangeAlloc = os.lib.range_alloc.RangeAlloc;
const Mutex      = os.thread.Mutex;

var sbrk_head: usize = undefined;

pub fn init(phys_high: usize) !void {
  os.log("Initializing vmm with base 0x{X}\n", .{phys_high});
  sbrk_mutex.init();
  sbrk_head = phys_high;
}

var sbrk_mutex = Mutex{};

pub fn nonbacked_sbrk(num_bytes: usize) ![]u8 {
  sbrk_mutex.lock();
  defer sbrk_mutex.unlock();

  const ret = sbrk_head;

  sbrk_head += num_bytes;

  return @intToPtr([*]u8, ret)[0..num_bytes];
}

pub fn sbrk(num_bytes: usize) ![]u8 {
  const ret = try nonbacked_sbrk(num_bytes);

  try paging.map(.{
    .virt = @ptrToInt(ret.ptr),
    .size = num_bytes,
    .perm = paging.rw(),
    .memtype = .MemoryWriteBack,
  });

  return ret;
}

/// Describes the lifetime of the memory aquired from an allocator
const Lifetime = enum {
  /// Ephemeral memory won't last for the entire uptime of the kernel,
  /// it can be freed to make it available to the rest of the system.
  Ephemeral,

  /// Eternal memory will remain allocated until system shutdown. It
  /// cannot be freed. Ever.
  Eternal,
};

/// Range allocator for backed memory
var range = RangeAlloc{.materialize_bytes = sbrk};

/// Range allocator for nonbacked memory
var nonbacked_range = RangeAlloc{.materialize_bytes = nonbacked_sbrk};

var ephemeral_alloc =
  std.heap.GeneralPurposeAllocator(.{
    .thread_safe = true,
    .MutexType = os.thread.Mutex,
  }){
    .backing_allocator = &range.allocator,
  };

/// The virtual memory is backed by physical pages.
/// You can dereference these pointers just like in your
/// normal programs
pub fn backed(
  lifetime: Lifetime,
) *std.mem.Allocator {
  switch(lifetime) {
    .Ephemeral => return &ephemeral_alloc.allocator,
    .Eternal   => return &range.allocator,
  }
}

/// The virtual memory is _NOT_ backed by physical pages.
/// If you dereference this memory, you _WILL_ get a page
/// fault. The pointers into this memory cannot be dereferenced
/// before mapping the memory to some physical memory.
pub fn nonbacked() *std.mem.Allocator {
  return &nonbacked_range.allocator;
}
