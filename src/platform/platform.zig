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

pub fn page_fault(addr: usize, present: bool, access: PageFaultAccess) void {
  if(present)
    assert(access != .Read);
}
