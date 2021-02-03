const std = @import("std");
const os = @import("root").os;

const paging     = os.memory.paging;
const RangeAlloc = os.lib.range_alloc.RangeAlloc;
const Mutex      = os.thread.Mutex;

var sbrk_head: u64 = undefined;

pub fn init(phys_high: u64) !void {
  os.log("Initializing vmm with base 0x{X}\n", .{phys_high});
  sbrk_mutex.init();
  sbrk_head = phys_high;
}

var sbrk_mutex = Mutex{};

pub fn nonbacked_sbrk(num_bytes: u64) ![]u8 {
  sbrk_mutex.lock();
  defer sbrk_mutex.unlock();

  const ret = sbrk_head;
  os.log("VMM: sbrk(0x{X}) = 0x{X}\n", .{num_bytes, ret});

  sbrk_head += num_bytes;

  return @intToPtr([*]u8, ret)[0..num_bytes];
}

pub fn sbrk(num_bytes: u64) ![]u8 {
  const ret = try nonbacked_sbrk(num_bytes);

  try paging.map(.{
    .virt = @ptrToInt(ret.ptr),
    .size = num_bytes,
    .perm = paging.rw(),
    .memtype = .MemoryWritethrough,
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

fn locked_alloc() type {
  const std_allocator =
      std.heap.GeneralPurposeAllocator(.{.thread_safe = false}){
        .backing_allocator = &range.allocator,
      };

  return struct {
    frontend_alloc: std.mem.Allocator = .{
      .allocFn = alloc,
      .resizeFn = resize,
    },

    // We use our own mutex since we don't spinlock, we do other useful work
    mutex: Mutex = .{},
    gpalloc: @TypeOf(std_allocator) = std_allocator,

    fn alloc(frontend_alloc: *std.mem.Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) ![]u8 {
      const self = @fieldParentPtr(@This(), "frontend_alloc", frontend_alloc);
      self.mutex.lock();
      defer self.mutex.unlock();

      return self.gpalloc.allocator.allocFn(&self.gpalloc.allocator, len, ptr_align, len_align, ret_addr);
    }

    fn resize(frontend_alloc: *std.mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, len_align: u29, ret_addr: usize) !usize {
      const self = @fieldParentPtr(@This(), "frontend_alloc", frontend_alloc);
      self.mutex.lock();
      defer self.mutex.unlock();

      return self.gpalloc.allocator.resizeFn(&self.gpalloc.allocator, old_mem, old_align, new_size, len_align, ret_addr);
    }
  };
}

// When you want to allocate memory you have to decide

/// Range allocator for backed memory
var range = RangeAlloc{.materialize_bytes = sbrk};

/// Range allocator for nonbacked memory
var nonbacked_range = RangeAlloc{.materialize_bytes = nonbacked_sbrk};

var ephemeral_alloc = locked_alloc(){};

/// The virtual memory is backed by physical pages.
/// You can dereference these pointers just like in your
/// normal programs
pub fn backed(
  lifetime: Lifetime,
) *std.mem.Allocator {
  switch(lifetime) {
    .Ephemeral => return &ephemeral_alloc.frontend_alloc,
    .Eternal   => return &range.allocator,
  }
}

/// The virtual memory is _NOT_ backed by physical pages.
/// If you dereference this memory, you _WILL_ get a page
/// fault. The pointers into this memory cannot be dereferenced
/// before mapping the memory to some physical memory.
pub fn nonbacked() *std.mem.allocator {
  return nonbacked_range.allocator;
}
