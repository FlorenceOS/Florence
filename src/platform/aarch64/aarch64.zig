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
  log("The platform is alive!\n", .{});
}

pub fn debugputch(val: u8) void {

}

pub const InterruptFrame = struct {
  mode: u64,
  _: u64,
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

export fn interrupt64_common() callconv(.Naked) void {
  asm volatile(
    \\STP X1,  X0,  [SP, #-0x10]!
    \\STP X3,  X2,  [SP, #-0x10]!
    \\STP X5,  X4,  [SP, #-0x10]!
    \\STP X7,  X6,  [SP, #-0x10]!
    \\STP X9,  X8,  [SP, #-0x10]!
    \\STP X11, X10, [SP, #-0x10]!
    \\STP X13, X12, [SP, #-0x10]!
    \\STP X15, X14, [SP, #-0x10]!
    \\STP X17, X16, [SP, #-0x10]!
    \\STP X19, X18, [SP, #-0x10]!
    \\STP X21, X20, [SP, #-0x10]!
    \\STP X23, X22, [SP, #-0x10]!
    \\STP X25, X24, [SP, #-0x10]!
    \\STP X27, X26, [SP, #-0x10]!
    \\STP X29, X28, [SP, #-0x10]!
    \\STP X31, X30, [SP, #-0x10]!
    \\MOV X0, #64
    \\STP X0,  XZR, [SP, #-0x10]!
    \\MOV X0,  SP
    \\BL interrupt64_handler
    \\LDP XZR, XZR, [SP], 0x10
    \\LDP X31, X30, [SP], 0x10
    \\LDP X29, X28, [SP], 0x10
    \\LDP X27, X26, [SP], 0x10
    \\LDP X25, X24, [SP], 0x10
    \\LDP X23, X22, [SP], 0x10
    \\LDP X21, X20, [SP], 0x10
    \\LDP X19, X18, [SP], 0x10
    \\LDP X17, X16, [SP], 0x10
    \\LDP X15, X14, [SP], 0x10
    \\LDP X13, X12, [SP], 0x10
    \\LDP X11, X10, [SP], 0x10
    \\LDP X9,  X8,  [SP], 0x10
    \\LDP X7,  X6,  [SP], 0x10
    \\LDP X5,  X4,  [SP], 0x10
    \\LDP X3,  X2,  [SP], 0x10
    \\LDP X1,  X0,  [SP], 0x10
    \\ERET
  );
}

export fn interrupt32_common() callconv(.Naked) void {
  asm volatile(
    \\STP W0,  WZR, [SP, #-0x8]!
    \\STP W1,  WZR, [SP, #-0x8]!
    \\STP W2,  WZR, [SP, #-0x8]!
    \\STP W3,  WZR, [SP, #-0x8]!
    \\STP W4,  WZR, [SP, #-0x8]!
    \\STP W5,  WZR, [SP, #-0x8]!
    \\STP W6,  WZR, [SP, #-0x8]!
    \\STP W7,  WZR, [SP, #-0x8]!
    \\STP W8,  WZR, [SP, #-0x8]!
    \\STP W9,  WZR, [SP, #-0x8]!
    \\STP W10, WZR, [SP, #-0x8]!
    \\STP W11, WZR, [SP, #-0x8]!
    \\STP W12, WZR, [SP, #-0x8]!
    \\STP W13, WZR, [SP, #-0x8]!
    \\STP W14, WZR, [SP, #-0x8]!
    \\STP W15, WZR, [SP, #-0x8]!
    \\STP XZR, XZR, [SP, #-0x10]! // 16, 17
    \\STP XZR, XZR, [SP, #-0x10]! // 18, 19
    \\STP XZR, XZR, [SP, #-0x10]! // 20, 21
    \\STP XZR, XZR, [SP, #-0x10]! // 22, 23
    \\STP XZR, XZR, [SP, #-0x10]! // 24, 25
    \\STP XZR, XZR, [SP, #-0x10]! // 26, 27
    \\STP XZR, XZR, [SP, #-0x10]! // 28, 29
    \\STP XZR, XZR, [SP, #-0x10]! // 30, 31
    \\MOV X0, #64
    \\STP X0,  XZR, [SP, #-0x10]!
    \\MOV X0,  SP
    \\BL interrupt32_handler
    \\ADD SP,  SP,  0x80 // 16 - 31
    \\LDP W15, WZR, [SP], 0x8
    \\LDP W14, WZR, [SP], 0x8
    \\LDP W13, WZR, [SP], 0x8
    \\LDP W12, WZR, [SP], 0x8
    \\LDP W11, WZR, [SP], 0x8
    \\LDP W10, WZR, [SP], 0x8
    \\LDP W9,  WZR, [SP], 0x8
    \\LDP W8,  WZR, [SP], 0x8
    \\LDP W7,  WZR, [SP], 0x8
    \\LDP W6,  WZR, [SP], 0x8
    \\LDP W5,  WZR, [SP], 0x8
    \\LDP W4,  WZR, [SP], 0x8
    \\LDP W3,  WZR, [SP], 0x8
    \\LDP W2,  WZR, [SP], 0x8
    \\LDP W1,  WZR, [SP], 0x8
    \\LDP W0,  WZR, [SP], 0x8
    \\RET
  );
}

comptime {
  asm(
    \\.balign 0x800
    \\.global exception_vector_table; exception_vector_table:
    \\.balign 0x80; B interrupt64_common // curr_el_sp0_sync
    \\.balign 0x80; B interrupt64_common // curr_el_sp0_irq
    \\.balign 0x80; B interrupt64_common // curr_el_sp0_fiq
    \\.balign 0x80; B interrupt64_common // curr_el_sp0_serror
    \\.balign 0x80; B interrupt64_common // curr_el_spx_sync
    \\.balign 0x80; B interrupt64_common // curr_el_spx_irq
    \\.balign 0x80; B interrupt64_common // curr_el_spx_fiq
    \\.balign 0x80; B interrupt64_common // curr_el_spx_serror
    \\.balign 0x80; B interrupt64_common // lower_el_aarch64_sync
    \\.balign 0x80; B interrupt64_common // lower_el_aarch64_irq
    \\.balign 0x80; B interrupt64_common // lower_el_aarch64_fiq
    \\.balign 0x80; B interrupt64_common // lower_el_aarch64_serror
    \\.balign 0x80; B interrupt32_common // lower_el_aarch32_sync
    \\.balign 0x80; B interrupt32_common // lower_el_aarch32_irq
    \\.balign 0x80; B interrupt32_common // lower_el_aarch32_fiq
    \\.balign 0x80; B interrupt32_common // lower_el_aarch32_serror
  );
}

extern const exception_vector_table: [0x800]u8;

pub fn platform_early_init() void {
  install_vector_table();
}

pub fn install_vector_table() void {
  log("Installing exception vector table at 0x{X}\n", .{@ptrToInt(&exception_vector_table[0])});
  asm volatile(
    \\MSR VBAR_EL1, %[evt]
    :
    : [evt] "r" (&exception_vector_table)
  );
}

export fn interrupt64_handler(frame: *InterruptFrame) void {
  log("Got a 64 bit interrupt or something idk\n", .{});
  while(true) { }
}

export fn interrupt32_handler(frame: *InterruptFrame) void {
  log("Got a 32 bit interrupt or something idk\n", .{});
  while(true) { }
}

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
