const acpi = @import("../acpi.zig");

const log = @import("../../logger.zig").log;

const std = @import("std");
const builtin = @import("builtin");

pub fn handle_madt(madt: []u8) void {
  log("APIC: Got MADT (size={x})\n", .{madt.len});

  var offset: u64 = 0x2C;
  while(offset + 2 <= madt.len) {
    const kind = madt[offset + 0];
    const size = madt[offset + 1];

    if(offset + size >= madt.len)
      break;

    switch(kind) {
      0 => {
        std.debug.assert(size >= 8);
        const apic_id = madt[offset + 3];
        const flags = std.mem.readInt(u32, madt[offset + 4..][0..4], builtin.endian);
        log("APIC: Processor: {}, flags = {}\n", .{apic_id, flags});
      },
      else => {
        log("APIC: Unknown MADT entry: {}\n", .{kind});
      },
    }

    offset += size;
  }
}
