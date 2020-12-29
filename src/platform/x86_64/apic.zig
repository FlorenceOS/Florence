const os = @import("root").os;
const std = @import("std");
const builtin = @import("builtin");

fn handle_processor(apic_id: u32) void {
  os.log("APIC: Processor LAPIC ID {}\n", .{apic_id});
}

pub fn handle_madt(madt: []u8) void {
  os.log("APIC: Got MADT (size={x})\n", .{madt.len});

  var offset: u64 = 0x2C;
  while(offset + 2 <= madt.len) {
    const kind = madt[offset + 0];
    const size = madt[offset + 1];

    if(offset + size >= madt.len)
      break;

    switch(kind) {
      0x00 => {
        std.debug.assert(size >= 8);
        const apic_id = madt[offset + 3];
        const flags = std.mem.readInt(u32, madt[offset + 4..][0..4], builtin.endian);
        if(flags & 0x3 != 0)
          handle_processor(@as(u32, apic_id));
      },
      0x01 => {
        std.debug.assert(size >= 12);
        os.log("APIC: TODO: I/O APIC\n", .{});
      },
      0x02 => {
        std.debug.assert(size >= 10);
        os.log("APIC: TODO: Interrupt Source Override\n", .{});
      },
      0x03 => {
        std.debug.assert(size >= 8);
        os.log("APIC: TODO: NMI source\n", .{});
      },
      0x04 => {
        std.debug.assert(size >= 6);
        os.log("APIC: TODO: LAPIC Non-maskable interrupt\n", .{});
      },
      0x05 => {
        std.debug.assert(size >= 12);
        os.log("APIC: TODO: LAPIC addr override\n", .{});
      },
      0x06 => {
        std.debug.assert(size >= 16);
        os.log("APIC: TODO: I/O SAPIC\n", .{});
      },
      0x07 => {
        std.debug.assert(size >= 17);
        os.log("APIC: TODO: Local SAPIC\n", .{});
      },
      0x08 => {
        std.debug.assert(size >= 16);
        os.log("APIC: TODO: Platform interrupt sources\n", .{});
      },
      0x09 => {
        std.debug.assert(size >= 16);
        const apic_id = std.mem.readInt(u32, madt[offset + 12..][0..4], builtin.endian);
        const flags   = std.mem.readInt(u32, madt[offset + 8..][0..4], builtin.endian);
        if(flags & 0x3 != 0)
          handle_processor(apic_id);
      },
      0x0A => {
        std.debug.assert(size >= 12);
        os.log("APIC: TODO: LX2APIC NMI\n", .{});
      },
      else => {
        os.log("APIC: Unknown MADT entry: 0x{X}\n", .{kind});
      },
    }

    offset += size;
  }
}
