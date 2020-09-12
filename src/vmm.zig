const pmm = @import("pmm.zig");
const paging = @import("paging.zig");
const libalign = @import("lib/align.zig");
const buddy_alloc = @import("lib/buddy.zig").buddy_alloc;

const page_size = @import("platform.zig").page_sizes[0];

const log = @import("logger.zig").log;

const slab_sizes = [_]u64 {
  0x20,
  0x80,
  0x100,
};

pub fn alloc_eternal(comptime T: type, size: u64) ![]T {
  return alloc_size(T, size);
}

pub fn alloc_size(comptime T: type, size: u64) ![]T {
  return @intToPtr([*]T, try alloc_size_impl(allocated_bytes(T, size)))[0..size];
}

pub fn free_size(comptime T: type, data: []T) !void {
  return free_size_impl(@ptrToInt(&T[0]), allocated_bytes(T, data.size));
}

pub fn good_size(comptime T: type, least: u64) u64 {
  return allocated_bytes(T, least) / @sizeOf(T);
}

fn allocated_bytes(comptime T: type, least: u64) u64 {
  return good_bytes(@sizeOf(T) * least);
}

fn good_bytes(least_bytes: u64) u64 {
  inline for(slab_sizes) |slab_max_bytes| {
    if(least_bytes <= slab_max_bytes)
      return slab_max_bytes;
  }

  // Then just round up to page size
  return libalign.align_up(u64, page_size, least_bytes);
}

const RangeEntry = struct {
  start: u64,
  size: u64,

  next: *RangeEntry,
};

fn make_slab_space() u64 {
  const phys = pmm.alloc_phys(page_size);
  errdefer pmm.free_phys(phys, page_size);
}

const heap_base = 0xFFFFFF8000000000;
const heap_size = 0x8000000;

var heap_alloc: buddy_alloc(heap_size, page_size, heap_base) = undefined;

fn free_size_impl(ptr: u64, size: u64) !void {
  const round_up_sz = libalign.align_up(u64, page_size, size);

  // Unmap everything but the first page, the allocator needs it
  if(round_up_sz > page_size) {
    try paging.unmap(.{
      .virt = ptr + page_size,
      .size = round_up_sz - page_size,
      .reclaim_pages = true,
    });

    errdefer paging.map(.{
      .virt = ptr + page_size,
      .size = round_up_sz - page_size,
      .perm = paging.data(),
    });
  }

  try heap_alloc.free_size(size, ptr);
}

fn alloc_size_impl(size: u64) !u64 {
  // Just allocate and map this size
  const round_up_sz = libalign.align_up(u64, page_size, size);

  const ret = try alloc_virt(round_up_sz);
  errdefer free_virt(round_up_sz, ret) catch unreachable;

  // First page of this is already mapped
  if(round_up_sz > page_size) {
    try paging.map(.{
      .virt = ret + page_size,
      .size = round_up_sz - page_size,
      .perm = paging.data(),
    });

    errdefer paging.unmap(.{
      .virt = ret + page_size,
      .size = round_up_sz - page_size,
      .reclaim_pages = true,
    });
  }

  return ret;
}

pub fn alloc_virt(size: u64) !u64 {
  return heap_alloc.alloc_size(size);
}

pub fn free_virt(size: u64, value: u64) !void {
  return heap_alloc.free_size(size, value);
}

pub fn init() !void {
  try heap_alloc.init();
  errdefer heap_alloc.deinit() catch unreachable;
}
