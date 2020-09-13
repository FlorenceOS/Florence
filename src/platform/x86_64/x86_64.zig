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

pub const page_table_entry = packed struct {
  present: u1,
  writable: u1,
  user: u1,
  writethrough: u1,
  cache_disable: u1,
  accessed: u1,
  ignored_6: u1,
  is_mapping_bit: u1,
  ignored_8: u4,
  physaddr_bits: u51,
  execute_disable: u1,

  pub fn is_present(self: *const page_table_entry, comptime level: usize) bool {
    return self.present != 0;
  }

  pub fn clear(self: *page_table_entry, comptime level: usize) void {
    self.present = 0;
  }

  pub fn is_mapping(self: *const page_table_entry, comptime level: usize) bool {
    return self.is_present(level) and self.is_mapping_bit != 0;
  }

  pub fn is_table(self: *const page_table_entry, comptime level: usize) bool {
    return self.is_present(level) and !self.is_mapping(level);
  }

  pub fn physaddr(self: *const page_table_entry, comptime level: usize) u64 {
    return self.physaddr_bits << 12;
  }

  pub fn get_table(self: *const page_table_entry, comptime level: usize) !*page_table {
    if(!self.is_table(level))
      return error.IsNotTable;

    return &pmm.access_phys(page_table, self.physaddr(level))[0];
  }

  fn set_physaddr(self: *page_table_entry, comptime level: usize, addr: u64) void {
    self.physaddr_bits = @intCast(u51, addr >> 12);
  }

  pub fn set_table(self: *page_table_entry, comptime level: usize, addr: usize, perms: paging_perms) !void {
    if(self.is_present(level))
      return error.AlreadyPresent;

    self.present = 1;
    self.is_mapping_bit = 0;
    self.set_physaddr(addr);
    self.writable        =  perms.writable;
    self.user            =  perms.user;
    self.execute_disable = ~perms.executable;
    self.writethrough    = 1;
    self.cache_disable   = 0;
  }

  pub fn set_mapping(self: *page_table_entry, comptime level: usize, addr: usize, perms: paging_perms) !void {
    if(self.is_present(level))
      return error.AlreadyPresent;

    self.present = 1;
    self.is_mapping_bit = 1;
    self.set_physaddr(addr);
    self.set_mapping_perms(perms) catch unreachable;
  }

  pub fn add_table_perms(self: *page_table_entry, comptime level: usize, perms: paging_perms) !void {
    if(!self.is_table(level))
      return error.IsNotTable;
    
    self.writable        |=  perms.writable;
    self.user            |=  perms.user;
    self.execute_disable &= ~perms.executable;
  }

  pub fn set_mapping_perms(self: *page_table_entry, perms: paging_perms) !void {
    if(!self.is_mapping())
      return error.IsNotMapping;

    self.present         =  perms.present;
    self.writable        =  perms.writable;
    self.user            =  perms.user;
    self.writethrough    =  perms.writethrough;
    self.cache_disable   = ~perms.cacheable;
    self.execute_disable = ~perms.executable;
  }

  pub fn format(self: *const page_table_entry, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    if(!self.is_present()) {
      try writer.writeAll("Empty");
      return;
    }

    if(self.is_mapping()) {
      try writer.print("Mapping{{.phys = 0x{x}, .writable={}, .executable={}, .cache_disable={}", .{self.physaddr(), self.writable, ~self.execute_disable, self.cache_disable});

      if(self.writable != 0) {
        try writer.print(", .write_combining={}", .{~self.writethrough});
      }

      try writer.print("}}", .{});
      return;
    }
    if(self.is_table()) {
      try writer.print("Table{{.phys = 0x{x}, .writable={}, .executable={}}}", .{self.physaddr(), self.writable, ~self.execute_disable});
      return;
    }
    unreachable;
  }
};

comptime {
  assert(@bitSizeOf(page_table_entry) == 64);
}

pub const page_table = [512]u64;

fn table_index(table: *page_table, ind: usize) *page_table_entry {
  //return &table.*[ind]; NOPE OMEGALUL: https://github.com/ziglang/zig/issues/5451, for some reason it thinks page_table_entry is 9 bytes, not 8
  return @intToPtr(*page_table_entry, @ptrToInt(&table.*[0]) + ind * 8);
}

pub fn index_into_table(table: *page_table, vaddr: u64, level: usize) *page_table_entry {
  const ind = (vaddr >> (12 + @intCast(u6, level * 9))) & 0x1FF;
  return table_index(table, ind);
}

pub fn make_page_table() !u64 {
  const pt = try pmm.alloc_phys(0x1000);
  const pt_ptr = &pmm.access_phys(page_table, pt)[0];
  @memset(@ptrCast([*]u8, pt_ptr), 0x00, 0x1000);
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

  return asm volatile("rdmsr" : [_]"=A"(-> T) : [_]"{ecx}"(msr_num));
}

pub fn write_msr(comptime T: type, msr_num: u32, val: T) void {
  assert(T == u64);

  asm volatile("wrmsr" :: [_]"A"(val), [_]"{ecx}"(msr_num));
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
