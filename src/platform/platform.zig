const os = @import("root").os;

// Submodules
pub const acpi       = @import("acpi.zig");
pub const pci        = @import("pci.zig");
pub const devicetree = @import("devicetree.zig");

// Anything else comes from this platform specific file
const arch = @import("builtin").arch;
usingnamespace @import(
  switch(arch) {
    .aarch64 => "aarch64/aarch64.zig",
    .x86_64  => "x86_64/x86_64.zig",
    else => unreachable,
  }
);

const assert = @import("std").debug.assert;

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

pub const virt_slice = struct {
  ptr: u64,
  len: u64,
};

pub fn phys_ptr(comptime ptr_type: type) type {
  return struct {
    addr: u64,

    pub fn get(self: *const @This()) ptr_type {
      return @intToPtr(ptr_type, os.memory.pmm.phys_to_virt(self.addr));
    }

    pub fn from_int(a: u64) @This() {
      return .{
        .addr = a,
      };
    }

    pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
      try writer.print("phys 0x{X} {}", .{self.addr, self.get()});
    }
  };
}

pub const phys_bytes = struct {
  ptr: u64,
  len: u64,
};
