// Submodules
pub const acpi       = @import("acpi.zig");
pub const pci        = @import("pci.zig");
pub const devicetree = @import("devicetree.zig");

// Anything else comes from this platform specific file
usingnamespace @import(
  switch(@import("builtin").arch) {
    .aarch64 => "aarch64/aarch64.zig",
    .x86_64  => "x86_64/x86_64.zig",
    else => unreachable,
  }
);

const os = @import("root").os;
const std = @import("std");
const assert = std.debug.assert;

pub const PageFaultAccess = enum {
  Read,
  Write,
  InstructionFetch,
};

pub fn page_fault(addr: usize, present: bool, access: PageFaultAccess, frame: anytype) void {
  if(present)
    assert(access != .Read);

  frame.dump();
  frame.trace_stack();
}

pub fn hang() noreturn {
  _ = get_and_disable_interrupts();
  while(true) {
    await_interrupt();
    unreachable;
  }
}

pub const physaddr = os.lib.packed_int(memory.physaddr_bits, u64, 0);
pub const physpage = os.lib.packed_int(memory.physaddr_bits - memory.page_offset_bits, u64, memory.page_offset_bits);
pub const physsize = os.lib.packed_int(memory.physaddr_bits + 1, u64, 0);
pub const physpagesize = os.lib.packed_int(memory.physaddr_bits - memory.page_offset_bits + 1, u64, memory.page_offset_bits);

pub const virtaddr = os.lib.packed_int(memory.virt_bits, u64, 0);
pub const virtpage = os.lib.packed_int(memory.virt_bits - memory.page_offset_bits, u64, memory.page_offset_bits);
pub const virtsize = os.lib.packed_int(memory.virt_bits + 1, u64, 0);
pub const virtpagesize = os.lib.packed_int(memory.virt_bits - memory.page_offset_bits + 1, u64, memory.page_offset_bits);

pub fn phys_ptr(comptime ptr_type: type) type {
  return struct {
    addr: physaddr,

    pub fn get(self: *const @This()) ptr_type {
      return @intToPtr(ptr_type, os.memory.pmm.phys_to_virt(self.addr.get()));
    }

    pub fn init(a: u64) @This() {
      return .{
        .addr = physaddr.init(a),
      };
    }

    pub fn write(self: *@This(), addr: u64) void {
      self.addr.write(addr);
    }

    pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
      try writer.print("phys_ptr @0x{X}: {}", .{self.addr.get(), self.get()});
    }
  };
}

pub fn phys_ptr_cast(comptime to_type: type, val: anytype) phys_ptr(to_type) {
  return phys_ptr(to_type).init(val.addr.get());
}

pub fn phys_slice(comptime T: type) type {
  return struct {
    ptr: phys_ptr([*]T),
    len: usize,
  };
}
