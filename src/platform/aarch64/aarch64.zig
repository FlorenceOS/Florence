const std = @import("std");
const pmm = @import("../../pmm.zig");
const paging = @import("../../paging.zig");

const assert = std.debug.assert;

pub const page_sizes =
  [_]u64 {
    0x1000,
    0x200000,
    0x40000000,
    0x8000000000,
  };


// All mapping_ bits are ignored when it is a table,
// all table_   bits are ignored when it is a mapping.
// PXN is XN for EL3
pub const page_table_entry = packed struct {
  valid: u1,
  walk: u1,
  mapping_memory_attribute_index: u3, // 0 for device, 1 for normal
  mapping_nonsecure: u1,
  mapping_access: u2, // [2:1]=0 for RW, 2 for RO
  mapping_shareability: u2,
  mapping_accessed: u1,
  mapping_nonGlobal: u1,
  physaddr_bits: u36,
  zeroes: u4,
  mapping_hint: u1,
  mapping_pxn: u1,
  mapping_xn: u1,
  ignored: u4,
  table_pxn: u1,
  table_xn: u1,
  table_access: u2,
  table_nonsecure: u1,

  pub fn is_present(self: *const @This(), comptime level: usize) bool {
    return self.valid != 0;
  }

  pub fn clear(self: *@This(), comptime level: usize) void {
    self.valid = 0;
  }

  pub fn set_table(self: *@This(), comptime level: usize, table: u64, perm: paging.perms) !void {
    assert(level != 0);

    if(self.is_present(level))
      return error.AlreadyPresent;

    self.walk = 1;
    self.set_physaddr(level, table);

    self.table_access = 3;
    self.table_xn = 1;

    self.add_table_perms(level, perm) catch unreachable;
  }

  pub fn add_table_perms(self: *@This(), comptime level: usize, perm: paging.perms) !void {
    if(!self.is_table(level))
      return error.IsNotTable;

    if(perm.writable)
      self.table_access = 1;
    if(perm.executable)
      self.table_xn = 0;
  }

  pub fn set_mapping(self: *@This(), comptime level: usize, addr: u64, perm: paging.perms) !void {
    if(self.is_present(level))
      return error.AlreadyPresent;

    if(level == 0) {
      self.walk = 1;
    }
    else {
      self.walk = 0;
    }

    self.set_physaddr(level, addr);
  }

  pub fn set_physaddr(self: *@This(), comptime level: usize, addr: u64) void {
    self.physaddr_bits = @intCast(u36, addr >> 12);
  }

  pub fn is_mapping(self: *const @This(), comptime level: usize) bool {
    if(!self.is_present(level))
      return false;

    if(level == 0) {
      std.debug.assert(self.walk == 1);
      return true;
    }
    else {
      return self.walk == 0;
    }
  }

  pub fn is_table(self: *const @This(), comptime level: usize) bool {
    if(!self.is_present(level))
      return false;

    if(level == 0) {
      std.debug.assert(self.walk == 1);
      return false;
    }
    else {
      return self.walk == 1;
    }
  }

  pub fn get_table(self: *const @This(), comptime level: usize) !*page_table {
    if(!self.is_table(level))
      return error.IsNotTable;

    return &pmm.access_phys(page_table, self.physaddr(level))[0];
  }

  pub fn physaddr(self: *const @This(), comptime level: usize) u64 {
    return @as(u64, self.physaddr_bits) << 12;
  }
};

comptime {
  assert(@bitSizeOf(page_table_entry) == 64);
}

pub const page_table = [512]u64;

fn table_index(table: *page_table, ind: usize) *page_table_entry {
  return @ptrCast(*page_table_entry, &table[ind]);
}

pub fn index_into_table(table: *page_table, vaddr: usize, comptime level: usize) *page_table_entry {
  const index = (vaddr >> (12 + 9 * level)) & 0x1FF;
  return table_index(table, index);
}

pub fn current_paging_root() u64 {
  return asm (
    \\mrs %[result], TTBR0_EL1
    : [result] "=r" (-> u64)
  );
}

pub fn set_paging_root(val: u64) void {
  asm volatile(
    \\msr TTBR0_EL1, %[value]
    \\isb sy
    :
    : [value] "r" (val)
  );
}

pub fn spin_hint() void {
  asm volatile("YIELD");
}

pub fn make_page_table() !u64 {
  const pt = try pmm.alloc_phys(0x1000);
  const pt_ptr = &pmm.access_phys(page_table, pt)[0];
  @memset(@ptrCast([*]u8, pt_ptr), 0x00, 0x1000);
  return pt;
}

pub fn allowed_mapping_levels() usize {
  return 1;
}

pub fn platform_init() !void {
  
}

pub fn debugputch(val: u8) void {
  @intToPtr(*volatile u32, 0x9000000).* = val;
}
