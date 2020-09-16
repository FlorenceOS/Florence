const init_interrupts = @import("interrupts.zig").init_interrupts;
const setup_gdt = @import("gdt.zig").setup_gdt;

const pmm = @import("../../pmm.zig");
const paging = @import("../../paging.zig");
const pci = @import("../pci.zig");

const range = @import("../../lib/range.zig");

const std = @import("std");
const assert = std.debug.assert;

const log = @import("../../logger.zig").log;

pub const page_sizes =
  [_]u64 {
    0x1000,
    0x200000,
    0x40000000,
    0x8000000000,
  };

pub fn allowed_mapping_levels() u8 {
  return 2;
}

const paging_perms = @import("../../paging.zig").perms;

// https://github.com/ziglang/zig/issues/5451
// Just straight up doesn't work, everything breaks as page table entries has size 9
// according to the compiler
// present: u1,
// writable: u1,
// user: u1,
// writethrough: u1,
// cache_disable: u1,
// accessed: u1,
// ignored_6: u1,
// is_mapping_bit: u1,
// ignored_8: u4,
// physaddr_bits: u51,
// execute_disable: u1,

const phys_bitmask: u64 = ((@as(u64, 1) << 51) - 1) << 12;
const present_bit: u64 = 0x1;
const writable_bit: u64 = 0x2;
const user_bit: u64 = 0x4;
const writethrough_bit: u64 = 0x8;
const cache_disable_bit: u64 = 0x10;
const accessed_bit: u64 = 0x20;
const is_mapping_bit: u64 = 0x80;
const execute_disable_bit: u64 = 1 << 63;

pub const page_table_entry = packed struct {
  raw: u64,

  pub fn is_present(self: *const page_table_entry, comptime level: usize) bool {
    return (self.raw & present_bit) != 0;
  }

  pub fn clear(self: *page_table_entry, comptime level: usize) void {
    self.raw &= ~present_bit;
  }

  pub fn is_mapping(self: *const page_table_entry, comptime level: usize) bool {
    if(!self.is_present(level))
      return false;

    if(level == 0)
      return true;

    return (self.raw & is_mapping_bit) != 0;
  }

  pub fn is_table(self: *const page_table_entry, comptime level: usize) bool {
    if(!self.is_present(level) or level == 0)
      return false;

    return (self.raw & is_mapping_bit) == 0;
  }

  pub fn physaddr(self: *const page_table_entry, comptime level: usize) u64 {
    return self.raw & phys_bitmask;
  }

  pub fn get_table(self: *const page_table_entry, comptime level: usize) !*page_table {
    if(!self.is_table(level))
      return error.IsNotTable;

    return &pmm.access_phys(page_table, self.physaddr(level))[0];
  }

  fn set_physaddr(self: *page_table_entry, comptime level: usize, addr: u64) void {
    self.raw &= ~phys_bitmask;
    self.raw |=  addr;
  }

  pub fn set_table(self: *page_table_entry, comptime level: usize, addr: usize, perms: paging_perms) !void {
    assert(level != 0);

    if(self.is_present(level))
      return error.AlreadyPresent;

    self.raw |=  present_bit;
    self.raw &= ~is_mapping_bit;
    self.set_physaddr(level, addr);

    self.raw &= ~writable_bit;
    self.raw &= ~user_bit;
    self.raw |=  execute_disable_bit;
    self.raw |=  writethrough_bit;
    self.raw &= ~cache_disable_bit;

    self.add_table_perms(level, perms) catch unreachable;
  }

  pub fn set_mapping(self: *page_table_entry, comptime level: usize, addr: usize, perms: paging_perms) !void {
    if(self.is_present(level))
      return error.AlreadyPresent;

    self.raw |= present_bit;
    self.raw |= is_mapping_bit;
    self.set_physaddr(level, addr);

    self.raw |=  if(perms.writable)     writable_bit else 0;
    self.raw &= ~if(perms.executable)   execute_disable_bit else 0;
    self.raw |=  if(perms.user)         user_bit else 0;
    self.raw |=  if(perms.writethrough) writethrough_bit else 0;
    self.raw &= ~if(perms.cacheable)    cache_disable_bit else 0;
  }

  pub fn add_table_perms(self: *page_table_entry, comptime level: usize, perms: paging_perms) !void {
    if(!self.is_table(level))
      return error.IsNotTable;
    
    if(perms.writable)   self.raw |= writable_bit;
    if(perms.user)       self.raw |= user_bit;
    if(perms.executable) self.raw &= ~execute_disable_bit;
  }

  pub fn format(self: *const page_table_entry, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    if(!self.is_present(0)) {
      try writer.writeAll("Empty");
      return;
    }

    if(self.is_mapping(0)) {
      try writer.print("Mapping{{.phys = 0x{x}, .writable={}, .execute={}, .cacheable={}", .{self.physaddr(0), self.raw & writable_bit != 0, self.raw & execute_disable_bit == 0, self.raw & cache_disable_bit == 0});

      if((self.raw & writable_bit) != 0) {
        try writer.print(", .writethrough={}", .{self.raw & writethrough_bit != 0});
      }

      try writer.print("}}", .{});
      return;
    }
    if(self.is_table(0)) {
      try writer.print("Table{{.phys = 0x{x}, .writable={}, .execute={}}}", .{self.physaddr(0), self.raw & writable_bit != 0, self.raw & execute_disable_bit == 0});
      return;
    }
    unreachable;
  }
};

comptime {
  assert(@bitSizeOf(page_table_entry) == 64);
  assert(@sizeOf(page_table_entry) == 8);
}

pub const page_table = [512]page_table_entry;

fn table_index(table: *page_table, ind: usize) *page_table_entry {
  return &table.*[ind];
}

pub fn index_into_table(table: *page_table, vaddr: u64, level: usize) *page_table_entry {
  const ind = (vaddr >> (12 + @intCast(u6, level * 9))) & 0x1FF;
  return table_index(table, ind);
}

pub fn make_page_table() !u64 {
  const pt = try pmm.alloc_phys(0x1000);
  @memset(pmm.access_phys(u8, pt), 0x00, 0x1000);
  return pt;
}

pub fn set_paging_root(phys_paging_root: u64) void {
  asm volatile (
    "mov %[paging_root], %%cr3\n\t"
    :
    : [paging_root] "X" (phys_paging_root)
  );
}

pub fn current_paging_root() u64 {
  return asm volatile (
    "mov %%cr3, %[paging_root]\n\t"
    : [paging_root] "={rax}" (-> u64)
  ); 
}

pub fn prepare_paging() !void {
  IA32_EFER.write(IA32_EFER.read() | (1 << 11)); // NXE
}

pub fn platform_init() !void {
  try init_interrupts();
  setup_gdt();
}

pub fn read_msr(comptime T: type, msr_num: u32) T {
  assert(T == u64);

  var low: u32 = undefined;
  var high: u32 = undefined;
  asm volatile("rdmsr" : [_]"={eax}"(low), [_]"={edx}"(high) : [_]"{ecx}"(msr_num));
  return (@as(u64, high) << 32) | @as(u64, low);
}

pub fn write_msr(comptime T: type, msr_num: u32, val: T) void {
  assert(T == u64);

  const low = @intCast(u32, val & 0xFFFFFFFF);
  const high = @intCast(u32, val >> 32);
  asm volatile("wrmsr" :: [_]"{eax}"(low), [_]"{edx}"(high), [_]"{ecx}"(msr_num));
}

pub fn msr(comptime T: type, comptime msr_num: u32) type {
  return struct {
    pub fn read() T {
      return read_msr(T, msr_num);
    }

    pub fn write(val: T) void {
      write_msr(T, msr_num, val);
    }
  };
}

fn request(addr: pci.Addr, offset: pci.regoff) void {
  const val = 1 << 31
    | @as(u32, offset)
    | @as(u32, addr.function) << 8
    | @as(u32, addr.device) << 11
    | @as(u32, addr.bus) << 16
  ;

  outl(0xCF8, val);
}

pub fn pci_read(comptime T: type, addr: pci.Addr, offset: pci.regoff) T {
  request(addr, offset);
  return in(T, 0xCFC + @as(u16, offset % 4));
}

pub fn pci_write(comptime T: type, addr: pci.Addr, offset: pci.regoff, value: T) void {
  request(addr, offset);
  out(T, 0xCFC + @as(u16, offset % 4), value);
}

pub const IA32_APIC_BASE = msr(u64, 0x0000001B);
pub const IA32_EFER      = msr(u64, 0xC0000080);
pub const KernelGSBase   = msr(u64, 0xC0000102);

pub fn spin_hint() void {
  asm volatile("pause");
}

pub fn out(comptime T: type, port: u16, value: T) void {
  switch(T) {
    u8  => outb(port, value),
    u16 => outw(port, value),
    u32 => outw(port, value),
    else => @compileError("No out instruction for this type"),
  }
}

pub fn in(comptime T: type, port: u16) T {
  return switch(T) {
    u8  => inb(port),
    u16 => inw(port),
    u32 => inw(port),
    else => @compileError("No in instruction for this type"),
  };
}

pub fn outb(port: u16, val: u8) void {
  asm volatile (
    "outb %[val], %[port]\n\t"
    :
    : [val] "{al}"(val), [port] "N{dx}"(port)
  );
}

pub fn outw(port: u16, val: u16) void {
  asm volatile (
    "outw %[val], %[port]\n\t"
    :
    : [val] "{ax}"(val), [port] "N{dx}"(port)
  );
}

pub fn outl(port: u16, val: u32) void {
  asm volatile (
    "outl %[val], %[port]\n\t"
    :
    : [val] "{eax}"(val), [port] "N{dx}"(port)
  );
}

pub fn inb(port: u16) u8 {
  return asm volatile (
    "inb %[port], %[result]\n\t"
    : [result] "={al}" (-> u8)
    : [port]   "N{dx}" (port)
  );
}

pub fn inw(port: u16) u16 {
  return asm volatile (
    "inw %[port], %[result]\n\t"
    : [result] "={ax}" (-> u16)
    : [port]   "N{dx}" (port)
  );
}

pub fn inl(port: u16) u32 {
  return asm volatile (
    "inl %[port], %[result]\n\t"
    : [result] "={eax}" (-> u32)
    : [port]   "N{dx}" (port)
  );
}

pub fn debugputch(ch: u8) void {
  outb(0xe9, ch);
}
