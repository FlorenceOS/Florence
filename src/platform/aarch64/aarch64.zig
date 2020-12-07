const os = @import("root").os;
const std = @import("std");

const pmm       = os.memory.pmm;
const paging    = os.memory.paging;
const bf        = os.lib.bitfields;

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

pub const paging_root = struct {
  br0: u64,
  br1: u64,
};

const phys_bitmask: u64 = ((@as(u64, 1) << 36) - 1) << 12;

// D5.5.1
const shareability = .{
  .nonshareable = 0,
  // 1 reserved
  .outer = 2,
  .inner = 3,
};

pub const page_table_entry = extern union {
  raw: u64,

  present_bit: bf.boolean(u64, 0),
  walk_bit: bf.boolean(u64, 1),

  // For mappings
  mapping_xn:  bf.boolean(u64, 54), // eXecute Never
  mapping_wn:  bf.boolean(u64, 7),  // Write Never
  mapping_ns:  bf.boolean(u64, 5),  // NonSecure, outside EL3
  mapping_pxn: bf.boolean(u64, 53), // Privileged eXecute Never
  mapping_ng:  bf.boolean(u64, 11), // NonGlobal, has to match asid
  mapping_af:  bf.boolean(u64, 10), // Just set it

  mapping_sh: bf.bitfield(u64, 8, 2), // SHareability, 2 for normal memory
  mapping_ai: bf.bitfield(u64, 2, 3), // Memory attribute index into MAIR

  // For tables
  table_xn: bf.boolean(u64, 60),
  table_wn: bf.boolean(u64, 62),
  table_ns: bf.boolean(u64, 63),
  table_pxn: bf.boolean(u64, 59),

  pub fn is_present(self: *const @This(), comptime level: usize) bool {
    return self.present_bit.read();
  }

  pub fn clear(self: *@This(), comptime level: usize) void {
    self.present_bit.write(false);
  }

  pub fn set_table(self: *@This(), comptime level: usize, table: u64, perm: paging.perms) !void {
    assert(level != 0);

    if(self.is_present(level))
      return error.AlreadyPresent;

    self.raw = 0;

    self.raw = table;
    self.raw |= (1 << 63) | 0x3;
    return;

    // self.walk_bit.write(true);
    // self.present_bit.write(true);
    // self.table_xn.write(true);
    // self.table_wn.write(true);
    // self.table_ns.write(true);
    // self.table_pxn.write(false);

    // self.set_physaddr(level, table);

    // self.add_table_perms(level, perm) catch unreachable;
  }

  pub fn add_table_perms(self: *@This(), comptime level: usize, perm: paging.perms) !void {
    if(!self.is_table(level))
      return error.IsNotTable;

    if(perm.writable)   self.table_wn.write(false);
    if(perm.executable) self.table_xn.write(false);
  }

  pub fn set_mapping(self: *@This(), comptime level: usize, addr: u64, perm: paging.perms) !void {
    if(self.is_present(level))
      return error.AlreadyPresent;

    self.raw = 0;

    self.raw = addr;
    self.raw |= 0x623;

    var ai_value: u3 = undefined;

    if(perm.cacheable and perm.writethrough) {
      // Normal memory
      ai_value = 0;
    } else {
      if(!perm.cacheable and perm.writethrough) {
        // Device memory
        ai_value = 2;
      } else {
        return error.UnknownMappingPerms;
      }
    }

    self.mapping_ai.write(ai_value);

    return;

    // self.walk_bit.write(level == 0);
    // self.present_bit.write(true);
    // self.mapping_xn.write(!perm.executable);
    // self.mapping_pxn.write(!perm.executable);
    // self.mapping_wn.write(!perm.writable);

    // self.mapping_ns.write(true);
    // self.mapping_ng.write(true);
    // self.mapping_af.write(true);
    // self.mapping_sh.write(shareability.outer);

    // self.set_physaddr(level, addr);
  }

  pub fn set_physaddr(self: *@This(), comptime level: usize, addr: u64) void {
    self.raw &= ~phys_bitmask;
    self.raw |= addr & phys_bitmask;
  }

  pub fn is_mapping(self: *const @This(), comptime level: usize) bool {
    if(!self.is_present(level))
      return false;

    if(level == 0) {
      std.debug.assert(self.walk_bit.read());
      return true;
    }
    else {
      return !self.walk_bit.read();
    }
  }

  pub fn is_table(self: *const @This(), comptime level: usize) bool {
    if(!self.is_present(level))
      return false;

    if(level == 0) {
      std.debug.assert(self.walk_bit.read());
      return false;
    }
    else {
      return self.walk_bit.read();
    }
  }

  pub fn get_table(self: *const @This(), comptime level: usize) !*page_table {
    if(!self.is_table(level))
      return error.IsNotTable;

    return &pmm.access_phys(page_table, self.physaddr(level))[0];
  }

  pub fn physaddr(self: *const @This(), comptime level: usize) u64 {
    return @as(u64, self.raw & phys_bitmask);
  }

  pub fn format(self: *const page_table_entry, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    if(!self.is_present(0)) {
      try writer.writeAll("Empty");
      return;
    }

    try writer.print("PTE{{.phys = 0x{x:0>16}, .raw=0x{x:0>16}}}", .{self.physaddr(0), self.raw});
  }
};

comptime {
  assert(@sizeOf(page_table_entry) == 8);
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

fn mair_value() u64 {
  return 0
    | (0b11111111 << 0) // Normal, Write-back RW-Allocate non-transient
    | (0b00001100 << 8) // Device, GRE
    | (0b00000000 << 16) // Device, nGnRnE
  ;
}

pub fn set_paging_root(val: *paging_root) void {
  asm volatile(
    \\msr TTBR0_EL1, %[br0]
    \\msr TTBR1_EL1, %[br1]
    \\msr MAIR_EL1,  %[mair]
    \\dsb sy
    \\isb sy
    :
    : [br0] "r" (val.br0)
    , [br1] "r" (val.br1)
    , [mair] "r" (mair_value())
    : "memory"
  );
}

pub fn get_current_task() *os.thread.Task {
  return asm volatile(
    \\mrs %[result], TPIDR_EL1
    : [result] "=r" (-> *os.thread.Task)
  );
}

pub fn set_current_task(ptr: *os.thread.Task) void {
  asm volatile(
    \\msr TPIDR_EL1, %[result]
    :
    : [result] "r" (ptr)
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

pub fn invalidate_mapping(virt: usize) void {
  asm volatile(
    \\TLBI VAE1, %[virt]
    :
    : [virt] "r" (virt >> 12)
    : "memory"
  );
}

pub fn allowed_mapping_levels() usize {
  return 2;
}

pub fn platform_init() !void {
  os.log("The platform is alive!\n", .{});
}

pub fn debugputch(val: u8) void {

}

pub const InterruptState = bool;

pub fn get_and_disable_interrupts() InterruptState {
  // Get interrupt mask flag
  var daif = asm volatile("MRS %[daif_val], DAIF" : [daif_val] "=r" (-> u64));

  // Set the flag
  asm volatile("MSR DAIFSET, 2" ::: "memory");
  
  // Check if it was set
  return (daif >> 7) & 1 == 0;
}

pub fn set_interrupts(s: InterruptState) void {
  if(s) {
    // Enable interrupts
    asm volatile("MSR DAIFCLR, 2" ::: "memory");
  } else {
    // Disable interrupts
    asm volatile("MSR DAIFSET, 2" ::: "memory");
  }
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
  set_current_task(&bsp_task);
}

var bsp_task: os.thread.Task = .{};

pub fn self_exited() !?*os.thread.Task {
  const curr = get_current_task();
  
  if(curr == &bsp_task)
    return null;

  if(curr.platform_data.stack != null) {
    // TODO: Figure out how to free the stack while returning using it??
    // We can just leak it for now
    //try vmm.free_single(curr.platform_data.stack.?);
  }
  return curr;
}

pub fn install_vector_table() void {
  os.log("Installing exception vector table at 0x{X}\n", .{@ptrToInt(&exception_vector_table[0])});
  asm volatile(
    \\MSR VBAR_EL1, %[evt]
    :
    : [evt] "r" (&exception_vector_table)
  );
}

pub fn await_interrupt() void {
  asm volatile(
    \\ MSR DAIFCLR, 0xF
    \\ WFI
    \\ MSR DAIFSET, 0xF
    :
    :
    : "memory"
  );
}

export fn interrupt64_handler(frame: *InterruptFrame) void {
  const esr = asm volatile("MRS %[esr], ESR_EL1" : [esr] "=r" (-> u64));

  const ec = (esr >> 26) & 0x3f;
  const iss = esr & 0x1ffffff;

  if(ec == 0b111100) {
    os.log("BRK instruction execution in AArch64 state\n", .{});
    while(true) { }
  }

  switch(ec) {
    else => @panic("Unknown EC!"),
    0b00000000 => @panic("Unknown reason in EC!"),
    0b00100101 => @panic("Data abort without change in exception level"),
    0b00100001 => @panic("Instruction fault without change in exception level"),
    0b00010101 => {
      // SVC instruction execution in AArch64 state
      // Figure out which call this is

      switch(@intCast(u16, iss & 0xFFFF)) {
        else => @panic("Unknown SVC"),

        'Y' => @panic("yield_to_task"),
      }
    },
  }
}

export fn interrupt32_handler(frame: *InterruptFrame) void {
  os.log("Got a 32 bit interrupt or something idk\n", .{});
  while(true) { }
}

pub const TaskData = struct {
  stack: ?*[task_stack_size]u8 = null,
};

const task_stack_size = 1024 * 16;

pub fn yield_to_task(new_task: *os.thread.Task) void {
  asm volatile("SVC #'Y'" :: [_] "{x0}" (new_task));
}

pub fn new_task_call(new_task: *os.thread.Task, func: anytype, args: anytype) !void {
  @panic("yield");
}

pub fn prepare_paging() !void {

}
