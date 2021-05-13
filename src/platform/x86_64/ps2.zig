const std = @import("std");

const os = @import("root").os;
const apic = @import("apic.zig");
const ports = @import("ports.zig");
const kb = os.drivers.hid.keyboard;
const eoi = @import("apic.zig").eoi;

const Extendedness = enum {
  Extended,
  NotExtended,
};

pub var interrupt_vector: u8 = undefined;
pub var interrupt_gsi: u32 = undefined;

const scancode_extended = 0xE0;

fn parse_scancode(ext: Extendedness, scancode: u8) void {
  switch(ext) {
    .Extended => {
      switch(scancode) {
        0x2A => { // Print screen press
          std.debug.assert(wait_byte() == scancode_extended);
          std.debug.assert(wait_byte() == 0x37);
          state.event(.Press, .PrintScreen);
          return;
        },
        0xB7 => { // Print screen release
          std.debug.assert(wait_byte() == scancode_extended);
          std.debug.assert(wait_byte() == 0xAA);
          state.event(.Release, .PrintScreen);
          return;
        },
        else => { },
      }
    },
    .NotExtended => {
      switch(scancode) {
        0xE1 => {
          std.debug.assert(wait_byte() == 0x1D);
          std.debug.assert(wait_byte() == 0x45);
          std.debug.assert(wait_byte() == 0xE1);
          std.debug.assert(wait_byte() == 0x9D);
          std.debug.assert(wait_byte() == 0xC5);
          state.event(.Press, .PauseBreak);
          // There is no event for releasing this key,
          // so we just gotta pretend it's released instantly
          state.event(.Release, .PauseBreak);
          return;
        },
        else => { },
      }
    },
  }

  const loc = key_location(ext, scancode & 0x7F) catch return;

  if(scancode & 0x80 != 0) {
    state.event(.Release, loc);
  } else {
    state.event(.Press, loc);
  }
}

var state: kb.KeyboardState = .{};

fn has_byte() bool {
  return (ports.inb(0x64) & 1) != 0;
}

fn wait_byte() u8 {
  while(!has_byte()) { }
  return ports.inb(0x60);
}

pub fn handler(_: *os.platform.InterruptFrame) void {
  var ext: Extendedness = .NotExtended;

  var scancode = wait_byte();

  if(scancode == scancode_extended) {
    ext = .Extended;
    scancode = wait_byte();
  }

  parse_scancode(ext, scancode);

  eoi();
}

fn key_location(ext: Extendedness, scancode: u8) !kb.keys.Location {
  switch(ext) {
    .NotExtended => {
      return switch(scancode) {
        0x01 => .Escape,
        0x02 => .NumberKey1,
        0x03 => .NumberKey2,
        0x04 => .NumberKey3,
        0x05 => .NumberKey4,
        0x06 => .NumberKey5,
        0x07 => .NumberKey6,
        0x08 => .NumberKey7,
        0x09 => .NumberKey8,
        0x0A => .NumberKey9,
        0x0B => .NumberKey0,
        0x0C => .RightOf0,
        0x0D => .LeftOfBackspace,
        0x0E => .Backspace,
        0x0F => .Tab,
        0x10 => .Line1_1,
        0x11 => .Line1_2,
        0x12 => .Line1_3,
        0x13 => .Line1_4,
        0x14 => .Line1_5,
        0x15 => .Line1_6,
        0x16 => .Line1_7,
        0x17 => .Line1_8,
        0x18 => .Line1_9,
        0x19 => .Line1_10,
        0x1A => .Line1_11,
        0x1B => .Line1_12,
        0x1C => .Enter,
        0x1D => .LeftCtrl,
        0x1E => .Line2_1,
        0x1F => .Line2_2,
        0x20 => .Line2_3,
        0x21 => .Line2_4,
        0x22 => .Line2_5,
        0x23 => .Line2_6,
        0x24 => .Line2_7,
        0x25 => .Line2_8,
        0x26 => .Line2_9,
        0x27 => .Line2_10,
        0x28 => .Line2_11,
        0x29 => .LeftOf1,
        0x2A => .LeftShift,
        0x2B => .Line2_12,
        0x2C => .Line3_1,
        0x2D => .Line3_2,
        0x2E => .Line3_3,
        0x2F => .Line3_4,
        0x30 => .Line3_5,
        0x31 => .Line3_6,
        0x32 => .Line3_7,
        0x33 => .Line3_8,
        0x34 => .Line3_9,
        0x35 => .Line3_10,
        0x36 => .RightShift,
        0x37 => .NumpadMultiplication,
        0x38 => .LeftAlt,
        0x39 => .Spacebar,
        0x3A => .CapsLock,
        0x3B => .F1,
        0x3C => .F2,
        0x3D => .F3,
        0x3E => .F4,
        0x3F => .F5,
        0x40 => .F6,
        0x41 => .F7,
        0x42 => .F8,
        0x43 => .F9,
        0x44 => .F10,
        0x45 => .NumLock,
        0x46 => .ScrollLock,
        0x47 => .Numpad7,
        0x48 => .Numpad8,
        0x49 => .Numpad9,
        0x4A => .NumpadSubtraction,
        0x4B => .Numpad4,
        0x4C => .Numpad5,
        0x4D => .Numpad6,
        0x4E => .NumpadAddition,
        0x4F => .Numpad1,
        0x50 => .Numpad2,
        0x51 => .Numpad3,
        0x52 => .Numpad0,
        0x53 => .NumpadPoint,

        0x56 => .RightOfLeftShift,
        0x57 => .F11,
        0x58 => .F12,

        else => {
          os.log("PS2: Unhandled scancode 0x{X}\n", .{scancode});
          return error.UnknownScancode;
        },
      };
    },
    .Extended => {
      return switch(scancode) {
        0x10 => .MediaRewind,
        0x19 => .MediaForward,
        0x20 => .MediaMute,
        0x1C => .NumpadEnter,
        0x1D => .RightCtrl,
        0x22 => .MediaPausePlay,
        0x24 => .MediaStop,
        0x2E => .MediaVolumeDown,
        0x30 => .MediaVolumeUp,
        0x35 => .NumpadDivision,
        0x38 => .RightAlt,
        0x47 => .Home,
        0x48 => .ArrowUp,
        0x49 => .PageUp,
        0x4B => .ArrowLeft,
        0x4D => .ArrowRight,
        0x4F => .End,
        0x50 => .ArrowDown,
        0x51 => .PageDown,
        0x52 => .Insert,
        0x53 => .Delete,
        0x5B => .LeftSuper,
        0x5C => .RightSuper,
        0x5D => .OptionKey,

        else => {
          os.log("PS2: Unhandled extended scancode 0x{X}\n", .{scancode});
          return error.UnknownScancode; 
        },
      };
    },
  }
}
