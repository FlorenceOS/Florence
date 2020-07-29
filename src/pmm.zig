const platform = @import("platform.zig");
const assert = @import("std").debug.assert;
const lalign = @import("lib/align.zig");
const log = @import("logger.zig").log;

var free_roots = [_]u64{0} ** platform.page_sizes.len;

pub fn consume(phys: u64, size: u64) void {
  var sz = size;
  var pp = phys;

  outer: while(sz != 0) {
    inline for(platform.page_sizes) |psz, i| {
      // https://github.com/ziglang/zig/issues/2755
      var a = sz >= psz;
      var b = lalign.is_aligned(u64, psz, pp);
      if(a and b) {
        log("Freeing {} at level {}", .{pp, i});
        free_phys(pp, psz);
        sz -= psz;
        pp += psz;
        continue :outer;
      }
    }
    break;
  }
}

pub fn good_size(size: u64) u64 {
  unreachable;
}

fn alloc_impl(comptime ind: u64) !u64 {
  if(free_roots[ind] == 0) {
    if(ind + 1 >= platform.page_sizes.len) 
      return error.OutOfMemory;

    var next = try alloc_impl(ind + 1);
    var next_size = platform.page_sizes[ind + 1];

    const current_size = platform.page_sizes[ind];

    while(next_size > current_size) {
      free_impl(next, ind);
      next += current_size;
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
  assert(size <= platform.page_sizes[0]);
  return alloc_impl(0);
}

fn free_impl(phys: u64, comptime ind: u64) void {
  const last = free_roots[ind];
  free_roots[ind] = phys;
  access_phys(u64, phys)[0] = last;
}

pub fn free_phys(phys: u64, comptime size: u64) void {
  assert(size <= platform.page_sizes[0]);
  free_impl(phys, 0);
}

var phys_base: u64 = 0;

pub fn set_phys_base(base: u64) void {
  phys_base = base;
}

pub fn access_phys(comptime t: type, phys: u64) [*]t {
  return @intToPtr([*]t, phys + phys_base);
}
