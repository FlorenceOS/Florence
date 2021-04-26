const os = @import("root").os;
const std = @import("std");
const builtin = @import("builtin");

// LAPIC

var lapic: *volatile [0x100]u32 = undefined;

pub fn enable() void {
  const phy = IA32_APIC_BASE.read() & 0xFFFFF000; // ignore flags
  lapic = os.platform.phys_ptr(*volatile [0x100]u32).from_int(phy).get_uncached();
  lapic[SPURIOUS] |= 0x1FF; // bit 8 = lapic enable, 0xFF = spurious vector
}

pub fn eoi() void {
  lapic[EOI] = 0;
}

pub fn timer(ticks: u32, div: u32, vec: u32) void {
  lapic[LVT_TIMER] = vec | TIMER_MODE_PERIODIC;
  lapic[TIMER_DIV] = div;
  lapic[TIMER_INITCNT] = ticks;
}


// ACPI information

fn handle_processor(apic_id: u32) void {
  
}

fn handle_interrupt_source_override(bus: u8, source: u8, global_system_interrupt: u32, flags: u16) void {

}

pub fn handle_madt(madt: []u8) void {
  os.log("APIC: Got MADT (size={x})\n", .{madt.len});

  var offset: u64 = 0x2C;
  while(offset + 2 <= madt.len) {
    const kind = madt[offset + 0];
    const size = madt[offset + 1];

    const data = madt[offset .. offset + size];

    if(offset + size >= madt.len)
      break;

    switch(kind) {
      0x00 => {
        std.debug.assert(size >= 8);
        const apic_id = data[3];
        const flags = std.mem.readIntNative(u32, data[4..8]);
        if(flags & 0x3 != 0)
          handle_processor(@as(u32, apic_id));
      },
      0x01 => {
        std.debug.assert(size >= 12);
        os.log("APIC: TODO: I/O APIC\n", .{});
      },
      0x02 => {
        std.debug.assert(size >= 10);
        const bus = data[2];
        const source = data[3];
        const global_system_interrupt = std.mem.readIntNative(u32, data[4..8]);
        const flags = std.mem.readIntNative(u16, data[8..10]);
        handle_interrupt_source_override(bus, source, global_system_interrupt, flags);
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
        const flags   = std.mem.readIntNative(u32, data[8..12]);
        const apic_id = std.mem.readIntNative(u32, data[12..16]);
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

const IA32_APIC_BASE = @import("regs.zig").MSR(u64, 0x0000001B);
const LVT_TIMER = 0x320 / 4;
const TIMER_MODE_PERIODIC = 1 << 17;
const TIMER_DIV = 0x3E0 / 4;
const TIMER_INITCNT = 0x380 / 4;
const SPURIOUS = 0xF0 / 4;
const EOI = 0xB0 / 4;
