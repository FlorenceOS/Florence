const os = @import("root").os;
const std = @import("std");

// Submodules
pub const acpi       = @import("acpi.zig");
pub const pci        = @import("pci.zig");
pub const devicetree = @import("devicetree.zig");
pub const smp        = @import("smp.zig");

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

pub fn set_current_task(task_ptr: *os.thread.Task) void {
  thread.get_current_cpu().current_task = task_ptr;
}

pub fn get_current_task() *os.thread.Task {
  return thread.get_current_cpu().current_task;
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

pub fn phys_slice(comptime T: type) type {
  return struct {
    ptr: phys_ptr([*]T),
    len: u64,

    pub fn init(addr: u64, len: u64) @This() {
      return .{
        .ptr = phys_ptr([*]T).from_int(addr),
        .len = len,
      };
    }

    pub fn to_slice(self: *const @This()) []T {
      return self.ptr.get()[0..self.len];
    }

    pub fn remap(self: *const @This(), memtype: os.platform.paging.MemoryType) !void {
      return os.memory.paging.remap_phys_size(.{
        .phys = self.ptr.addr,
        .size = @sizeOf(T) * self.len,
        .memtype = memtype,
      });
    }
  };
}

pub const PhysBytes = struct {
  ptr: u64,
  len: u64,
};
