const std = @import("std");
const pmm = @import("../../pmm.zig");
const scheduler = @import("../../scheduler.zig");
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

pub fn current_paging_root() paging_root {
  return .{
    .br0 = asm("mrs %[result], TTBR0_EL1": [result] "=r" (-> u64)),
    .br1 = asm("mrs %[result], TTBR1_EL1": [result] "=r" (-> u64)),
  };
}

pub fn set_paging_root(val: *paging_root) void {
  asm volatile(
    \\msr TTBR0_EL1, %[br0]
    \\msr TTBR1_EL1, %[br1]
    \\isb sy
    :
    : [br0] "r" (val.br0)
    , [br1] "r" (val.br1)
    : "memory"
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

pub fn make_paging_root() !paging_root {
  const br0 = try make_page_table();
  errdefer pmm.free_phys(br0, 0x1000);

  const br1 = try make_page_table();
  errdefer pmm.free_phys(br1, 0x1000);

  return paging_root{
    .br0 = br0,
    .br1 = br1,
  };
}

pub fn root_table(virt: u64, root: paging_root) *page_table {
  return pmm.access_phys_single(page_table, switch(virt >> 63) {
    0 => root.br0,
    1 => root.br1,
    else => unreachable,
  });
}

pub fn root_tables(root: *paging_root) [2]*page_table {
  return [_]*page_table {
    pmm.access_phys_single(page_table, root.br0),
    pmm.access_phys_single(page_table, root.br1),
  };
}

pub fn allowed_mapping_levels() usize {
  return 1;
}

pub fn platform_init() !void {
  
}

pub fn debugputch(val: u8) void {
  @intToPtr(*volatile u32, 0x9000000).* = val;
}

pub const InterruptFrame = struct {
  x31: u64,
  x30: u64,
  x29: u64,
  x28: u64,
  x27: u64,
  x26: u64,
  x25: u64,
  x24: u64,
  x23: u64,
  x22: u64,
  x21: u64,
  x20: u64,
  x19: u64,
  x18: u64,
  x17: u64,
  x16: u64,
  x15: u64,
  x14: u64,
  x13: u64,
  x12: u64,
  x11: u64,
  x10: u64,
  x9: u64,
  x8: u64,
  x7: u64,
  x6: u64,
  x5: u64,
  x4: u64,
  x3: u64,
  x2: u64,
  x1: u64,
  x0: u64,
};

pub const TaskData = struct {
  stack: []u8,
};

pub fn exit_task() noreturn {
  @panic("exit_task");
}

pub fn yield() void {
  @panic("yield");
}

pub fn new_task_call(new_task: *scheduler.Task, func: anytype, args: anytype) !void {
  @panic("yield");
}

pub fn prepare_paging() !void {

}
