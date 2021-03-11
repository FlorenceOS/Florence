const os = @import("root").os;
const assert = @import("std").debug.assert;

const interrupts = @import("interrupts.zig");
const gdt = @import("gdt.zig");

const num_handlers = interrupts.num_handlers;

const Idtr = packed struct {
  limit: u16,
  addr: u64,
};

pub var idt = [1]IdtEntry{undefined} ** num_handlers;

pub const InterruptHandler = fn func() callconv(.Naked) void;

pub fn load_idt() void {
  const idtr = Idtr {
    .addr = @ptrToInt(&idt[0]),
    .limit = @sizeOf(@TypeOf(idt)) - 1,
  };

  asm volatile(
    \\  lidt (%[idtr_addr])
    :
    : [idtr_addr] "r" (&idtr)
  );
}

pub fn entry(handler: InterruptHandler, interrupt: bool, priv_level: u2, ist: u3) IdtEntry {
  return encode(
    @ptrToInt(handler), // addr
    ist, // ist
    if (interrupt) 0xE else 0xF, // gate_type
    0, // storage
    priv_level, // priv_level
    1, // present
  );
}

pub const IdtEntry = packed struct {
  addr_low: u16,
  selector: u16,
  ist: u3,
  space: u5 = 0,
  gate_type: u4,
  storage: u1,
  priv_level: u2,
  present: u1,
  addr_mid: u16,
  addr_high: u32,
  zeroes: u32 = 0,
};

pub fn encode(addr: u64, ist: u3, gate_type: u4, storage: u1, priv_level: u2, present: u1) IdtEntry {
   const result = IdtEntry {
    .addr_low = @truncate(u16, addr),
    .addr_mid = @truncate(u16, addr >> 16),
    .addr_high = @truncate(u32, addr >> 32),
    .selector = gdt.selector.code64 | priv_level,
    .ist = ist,
    .gate_type = gate_type,
    .storage = storage,
    .priv_level = priv_level,
    .present = present,
  };
  const intrepr = @ptrCast(*u64, &result).*;
  os.log("")
}

comptime {
  assert(@sizeOf(IdtEntry) == 16);
}
