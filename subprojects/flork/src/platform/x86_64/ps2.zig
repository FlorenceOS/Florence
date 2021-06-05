usingnamespace @import("root").preamble;

const apic = @import("apic.zig");
const ports = @import("ports.zig");
const eoi = @import("apic.zig").eoi;
const kb = lib.input.keyboard;

const Extendedness = enum {
    Extended,
    NotExtended,
};

pub var kb_interrupt_vector: u8 = undefined;
pub var kb_interrupt_gsi: u32 = undefined;

const scancode_extended = 0xE0;

fn parse_scancode(ext: Extendedness, scancode: u8) !void {
    switch (ext) {
        .Extended => {
            switch (scancode) {
                0x2A => { // Print screen press
                    std.debug.assert(kb_wait_byte() == scancode_extended);
                    std.debug.assert(kb_wait_byte() == 0x37);
                    try state.event(.press, .printScreen);
                    return;
                },
                0xB7 => { // Print screen release
                    std.debug.assert(kb_wait_byte() == scancode_extended);
                    std.debug.assert(kb_wait_byte() == 0xAA);
                    try state.event(.release, .printScreen);
                    return;
                },
                else => {},
            }
        },
        .NotExtended => {
            switch (scancode) {
                0xE1 => {
                    std.debug.assert(kb_wait_byte() == 0x1D);
                    std.debug.assert(kb_wait_byte() == 0x45);
                    std.debug.assert(kb_wait_byte() == 0xE1);
                    std.debug.assert(kb_wait_byte() == 0x9D);
                    std.debug.assert(kb_wait_byte() == 0xC5);
                    try state.event(.press, .pauseBreak);
                    // There is no event for releasing this key,
                    // so we just gotta pretend it's released instantly
                    try state.event(.release, .pauseBreak);
                    return;
                },
                else => {},
            }
        },
    }

    const loc = key_location(ext, scancode & 0x7F) catch return;

    if (scancode & 0x80 != 0) {
        try state.event(.release, loc);
    } else {
        try state.event(.press, loc);
    }
}

var state: kb.state.KeyboardState = .{};

fn kb_has_byte() bool {
    return (ports.inb(0x64) & 1) != 0;
}

fn kb_wait_byte() u8 {
    while (!kb_has_byte()) {}
    return ports.inb(0x60);
}

fn handle_keyboard_interrupt() void {
    var ext: Extendedness = .NotExtended;

    var scancode = kb_wait_byte();

    if (scancode == scancode_extended) {
        ext = .Extended;
        scancode = kb_wait_byte();
    }

    parse_scancode(ext, scancode) catch |err| switch (err) {
        error.UnknownKey => os.log("Unknown key!\n", .{}),
        else => {},
    };

    eoi();
}

pub fn kb_handler(_: *os.platform.InterruptFrame) void {
    while (kb_has_byte()) {
        handle_keyboard_interrupt();
    }
}

pub fn kb_init() void {
    const i = os.platform.get_and_disable_interrupts();
    defer os.platform.set_interrupts(i);

    if (kb_has_byte()) {
        handle_keyboard_interrupt();
    }
}

fn key_location(ext: Extendedness, scancode: u8) !kb.keys.Location {
    switch (ext) {
        .NotExtended => {
            return switch (scancode) {
                0x01 => .escape,
                0x02 => .numberKey1,
                0x03 => .numberKey2,
                0x04 => .numberKey3,
                0x05 => .numberKey4,
                0x06 => .numberKey5,
                0x07 => .numberKey6,
                0x08 => .numberKey7,
                0x09 => .numberKey8,
                0x0A => .numberKey9,
                0x0B => .numberKey0,
                0x0C => .rightOf0,
                0x0D => .leftOfbackspace,
                0x0E => .backspace,
                0x0F => .tab,
                0x10 => .line1_1,
                0x11 => .line1_2,
                0x12 => .line1_3,
                0x13 => .line1_4,
                0x14 => .line1_5,
                0x15 => .line1_6,
                0x16 => .line1_7,
                0x17 => .line1_8,
                0x18 => .line1_9,
                0x19 => .line1_10,
                0x1A => .line1_11,
                0x1B => .line1_12,
                0x1C => .enter,
                0x1D => .leftCtrl,
                0x1E => .line2_1,
                0x1F => .line2_2,
                0x20 => .line2_3,
                0x21 => .line2_4,
                0x22 => .line2_5,
                0x23 => .line2_6,
                0x24 => .line2_7,
                0x25 => .line2_8,
                0x26 => .line2_9,
                0x27 => .line2_10,
                0x28 => .line2_11,
                0x29 => .leftOf1,
                0x2A => .leftShift,
                0x2B => .line2_12,
                0x2C => .line3_1,
                0x2D => .line3_2,
                0x2E => .line3_3,
                0x2F => .line3_4,
                0x30 => .line3_5,
                0x31 => .line3_6,
                0x32 => .line3_7,
                0x33 => .line3_8,
                0x34 => .line3_9,
                0x35 => .line3_10,
                0x36 => .rightShift,
                0x37 => .numpadMultiplication,
                0x38 => .leftAlt,
                0x39 => .spacebar,
                0x3A => .capsLock,
                0x3B => .f1,
                0x3C => .f2,
                0x3D => .f3,
                0x3E => .f4,
                0x3F => .f5,
                0x40 => .f6,
                0x41 => .f7,
                0x42 => .f8,
                0x43 => .f9,
                0x44 => .f10,
                0x45 => .numLock,
                0x46 => .scrollLock,
                0x47 => .numpad7,
                0x48 => .numpad8,
                0x49 => .numpad9,
                0x4A => .numpadSubtraction,
                0x4B => .numpad4,
                0x4C => .numpad5,
                0x4D => .numpad6,
                0x4E => .numpadAddition,
                0x4F => .numpad1,
                0x50 => .numpad2,
                0x51 => .numpad3,
                0x52 => .numpad0,
                0x53 => .numpadPoint,

                0x56 => .rightOfleftShift,
                0x57 => .f11,
                0x58 => .f12,

                else => {
                    os.log("PS2: Unhandled scancode 0x{X}\n", .{scancode});
                    return error.UnknownScancode;
                },
            };
        },
        .Extended => {
            return switch (scancode) {
                0x10 => .mediaRewind,
                0x19 => .mediaForward,
                0x20 => .mediaMute,
                0x1C => .numpadEnter,
                0x1D => .rightCtrl,
                0x22 => .mediaPausePlay,
                0x24 => .mediaStop,
                0x2E => .mediaVolumeDown,
                0x30 => .mediaVolumeUp,
                0x35 => .numpadDivision,
                0x38 => .rightAlt,
                0x47 => .home,
                0x48 => .arrowUp,
                0x49 => .pageUp,
                0x4B => .arrowleft,
                0x4D => .arrowright,
                0x4F => .end,
                0x50 => .arrowDown,
                0x51 => .pageDown,
                0x52 => .insert,
                0x53 => .delete,
                0x5B => .leftSuper,
                0x5C => .rightSuper,
                0x5D => .optionKey,

                else => {
                    os.log("PS2: Unhandled extended scancode 0x{X}\n", .{scancode});
                    return error.UnknownScancode;
                },
            };
        },
    }
}
