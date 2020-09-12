const arch = @import("builtin").arch;

usingnamespace @import(
  switch(arch) {
    .aarch64 => "platform/aarch64/aarch64.zig",
    .x86_64  => "platform/x86_64/x86_64.zig",
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
