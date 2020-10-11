const std = @import("std");

const paging = @import("paging.zig");

const log = @import("logger.zig").log;

const GPAlloc = std.heap.GeneralPurposeAllocator;
const RangeAlloc = @import("lib/range_alloc.zig").RangeAlloc;
const Mutex = @import("scheduler.zig").Mutex;

var sbrk_head: u64 = undefined;

pub fn init(phys_high: u64) !void {
  log("Initializing vmm with base 0x{X}\n", .{phys_high});
  sbrk_head = phys_high;
}

var sbrk_mutex = Mutex{};

pub fn sbrk(num_bytes: u64) ![]u8 {
  sbrk_mutex.lock();
  defer sbrk_mutex.unlock();

  const ret = sbrk_head;
  log("VMM: sbrk(0x{X}) = 0x{X}\n", .{num_bytes, ret});

  try paging.map(.{
    .virt = ret,
    .size = num_bytes,
    .perm = paging.data(),
  });

  sbrk_head += num_bytes;

  return @intToPtr([*]u8, ret)[0..num_bytes];
}

fn threadsafe_gpalloc(comptime is_eternal: bool) type {
  return struct {
    allocator: std.mem.Allocator = .{
      .allocFn = alloc,
      .resizeFn = resize,
    },

    // We use our own mutex since we don't spinlock, we do other useful work
    mutex: Mutex = .{},
    gpalloc: GPAlloc(.{.thread_safe = false}) = .{
      .backing_allocator = range,
    },

    fn alloc(allocator: *std.mem.Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) ![]u8 {
      const self = @fieldParentPtr(@This(), "allocator", allocator);
      self.mutex.lock();
      defer self.mutex.unlock();

      return self.gpalloc.allocator.allocFn(&self.gpalloc.allocator, len, ptr_align, len_align, ret_addr);
    }

    fn resize(allocator: *std.mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, len_align: u29, ret_addr: usize) !usize {
      if(is_eternal) {
        @panic("Eternal resize!");
      }

      const self = @fieldParentPtr(@This(), "allocator", allocator);
      self.mutex.lock();
      defer self.mutex.unlock();

      return self.gpalloc.allocator.resizeFn(&self.gpalloc.allocator, old_mem, old_align, new_size, len_align, ret_addr);
    }
  };
}

// We split it into eternal and ephemeral allocations, since we don't want them to share pages
var range_allocator = RangeAlloc{};
pub const range = &range_allocator.allocator;

var ephemeral_alloc = threadsafe_gpalloc(false){};
pub const ephemeral = &ephemeral_alloc.allocator;

var eternal_alloc = threadsafe_gpalloc(true){};
pub const eternal = &eternal_alloc.allocator;
