const log = @import("../../logger.zig").log;
const pmm = @import("../../pmm.zig");
const assert = @import("std").debug.assert;

// struct IDTEntry {
//   u16 addrLow = 0;
//   u16 selector = 0;
//   u8  ist = 0;

//   union Attrib {
//     u8 repr = 0;
//     flo::Bitfield<0, 4, u8> gateType;
//     flo::Bitfield<4, 1, u8> storage;
//     flo::Bitfield<5, 2, u8> privLevel;
//     flo::Bitfield<7, 1, u8> present;
//   };

//   Attrib attributes;
//   u16 addrMid = 0;
//   u32 addrHigh = 0;
//   u32 zeroes = 0;
// };

const idt_entry = packed struct {
  addr_low: u16,
  selector: u16,
  ist: u8,
  gate_type: u4,
  storage: u1,
  priv_level: u2,
  present: u1,
  addr_mid: u16,
  addr_high: u32,
  zeroes: u32 = 0,
};

comptime {
  assert(@sizeOf(idt_entry) == 16);
}

const num_handlers = 0x100;

pub fn setup_idt() !void {
  log("Setting up IDT...\n", .{});

  // Allocate IDT
  const pmm_phys = @intToPtr(*[num_handlers]idt_entry, pmm.alloc_phys(@sizeOf(idt_entry) * num_handlers) catch return);
}
