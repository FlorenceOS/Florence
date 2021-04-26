// EXT Byte ->
//   F0 -> Read one scancode byte, interpret as one released scancode byte
//   Else -> Interpret as pressed ext scancode byte
//
// F0 -> Read one scancode byte, interpret as normal released byte
// Else-> Interpret as pressed normal scancode byte

const os = @import("root").os;
const apic = @import("apic.zig");
const ports = @import("ports.zig");

const EventType = enum {
  Press,
  Release,
};

const Extendedness = enum {
  Extended,
  NotExtended,
};

pub var interrupt_vector: u8 = undefined;
pub var interrupt_gsi: u32 = undefined;

fn parse_event(t: EventType, ext: Extendedness, scancode: u8) void {
  os.log("Event: {} {} Scancode: 0x{X}\n", .{@tagName(ext), @tagName(t), scancode});
}

fn wait_byte() u8 {
  while((ports.inb(0x64) & 1) == 0)
    os.platform.spin_hint();
  return ports.inb(0x60);
}

pub fn handler(_: *os.platform.InterruptFrame) void {
  var ext: Extendedness = .NotExtended;
  var t: EventType = .Press;
  
  var scancode = wait_byte();

  if(scancode == 0xE0) {
    ext = .Extended;
    scancode = wait_byte();
  }

  if(scancode == 0xF0) {
    t = .Release;
    scancode = wait_byte();
  }

  parse_event(t, ext, scancode);
  apic.eoi();
}
