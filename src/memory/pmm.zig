const os = @import("root").os;
const std = @import("std");

const assert   = std.debug.assert;
const platform = os.platform;
const lalign   = os.lib.libalign;

const page_sizes = platform.page_sizes;
var free_roots   = [_]u64{0} ** page_sizes.len;

var pmm_mutex    = os.thread.Mutex{};

const reverse_sizes = {
  var result: [page_sizes.len]u64 = undefined;
  for(page_sizes) |psz, i|
    result[page_sizes.len - i - 1] = psz;
  return result;
};

pub fn consume(phys: u64, size: u64) void {
  pmm_mutex.lock();
  defer pmm_mutex.unlock();

  var sz = size;
  var pp = phys;

  outer: while(sz != 0) {
    inline for(reverse_sizes) |psz, ri| {
      const i = page_sizes.len - ri - 1;
      if(sz >= psz and lalign.is_aligned(u64, psz, pp)) {
        free_impl(pp, i);
        sz -= psz;
        pp += psz;
        continue :outer;
      }
    }
    unreachable;
  }
}

pub fn good_size(size: u64) u64 {
  unreachable;
}

fn alloc_impl(ind: u64) error{OutOfMemory}!u64 {
  if(free_roots[ind] == 0) {
    if(ind + 1 >= page_sizes.len)
      return error.OutOfMemory;

    var next = try alloc_impl(ind + 1);
    var next_size = page_sizes[ind + 1];

    const current_size = page_sizes[ind];

    while(next_size > current_size) {
      free_impl(next, ind);
      next += current_size;
      next_size -= current_size;
    }

    return next;
  }
  else {
    const retval = free_roots[ind];

    free_roots[ind] = access_phys(u64, retval)[0];
    return retval;
  }
}

pub fn alloc_phys(size: u64) !u64 {
  inline for(page_sizes) |psz, i| {
    if(size <= psz) {
      pmm_mutex.lock();
      defer pmm_mutex.unlock();
      return alloc_impl(i);
    }
  }
  return error.PhysAllocTooSmall;
}

fn free_impl(phys: u64, ind: u64) void {
  const last = free_roots[ind];
  free_roots[ind] = phys;
  access_phys(u64, phys)[0] = last;
}

pub fn free_phys(phys: u64, size: u64) void {
  pmm_mutex.lock();
  defer pmm_mutex.unlock();

  inline for(reverse_sizes) |psz, ri| {
    const i = page_sizes.len - ri - 1;

    if(size <= psz and lalign.is_aligned(u64, psz, phys)) {
      return free_impl(phys, i);
    }
  }
  unreachable;
}

pub fn phys_to_virt(phys: u64) u64 {
  return os.memory.paging.CurrentContext.phys_to_virt(phys);
}

pub fn access_phys(comptime t: type, phys: u64) [*]t {
  return @intToPtr([*]t, phys_to_virt(phys));
}

pub fn access_phys_volatile(comptime t: type, phys: u64) [*]volatile t {
  return @ptrCast([*]volatile t, access_phys(t, phys));
}

pub fn access_phys_single(comptime t: type, phys: u64) *t {
  return &access_phys(t, phys)[0];
}

pub fn access_phys_single_volatile(comptime t: type, phys: u64) *volatile t {
  return @ptrCast(*volatile t, access_phys_single(t, phys));
}
