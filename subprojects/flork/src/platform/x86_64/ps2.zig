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
                    try state.event(.press, .print_screen);
                    return;
                },
                0xB7 => { // Print screen release
                    std.debug.assert(kb_wait_byte() == scancode_extended);
                    std.debug.assert(kb_wait_byte() == 0xAA);
                    try state.event(.release, .print_screen);
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
                    try state.event(.press, .pause_break);
                    // There is no event for releasing this key,
                    // so we just gotta pretend it's released instantly
                    try state.event(.release, .pause_break);
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
}

pub fn kb_handler(_: *os.platform.InterruptFrame) void {
    while (kb_has_byte()) {
        handle_keyboard_interrupt();
    }

    eoi();
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
                0x02 => .number_key1,
                0x03 => .number_key2,
                0x04 => .number_key3,
                0x05 => .number_key4,
                0x06 => .number_key5,
                0x07 => .number_key6,
                0x08 => .number_key7,
                0x09 => .number_key8,
                0x0A => .number_key9,
                0x0B => .number_key0,
                0x0C => .right_of0,
                0x0D => .left_of_backspace,
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
                0x1D => .left_ctrl,
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
                0x29 => .left_of1,
                0x2A => .left_shift,
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
                0x36 => .right_shift,
                0x37 => .numpad_mul,
                0x38 => .left_alt,
                0x39 => .spacebar,
                0x3A => .capslock,
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
                0x45 => .numlock,
                0x46 => .scroll_lock,
                0x47 => .numpad7,
                0x48 => .numpad8,
                0x49 => .numpad9,
                0x4A => .numpad_sub,
                0x4B => .numpad4,
                0x4C => .numpad5,
                0x4D => .numpad6,
                0x4E => .numpad_add,
                0x4F => .numpad1,
                0x50 => .numpad2,
                0x51 => .numpad3,
                0x52 => .numpad0,
                0x53 => .numpad_point,

                0x56 => .right_of_left_shift,
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
                0x10 => .media_rewind,
                0x19 => .media_forward,
                0x20 => .media_mute,
                0x1C => .numpad_enter,
                0x1D => .right_ctrl,
                0x22 => .media_pause_play,
                0x24 => .media_stop,
                0x2E => .media_volume_down,
                0x30 => .media_volume_up,
                0x35 => .numpad_div,
                0x38 => .right_alt,
                0x47 => .home,
                0x48 => .arrow_up,
                0x49 => .page_up,
                0x4B => .arrow_left,
                0x4D => .arrow_right,
                0x4F => .end,
                0x50 => .arrow_down,
                0x51 => .page_down,
                0x52 => .insert,
                0x53 => .delete,
                0x5B => .left_super,
                0x5C => .right_super,
                0x5D => .option_key,

                else => {
                    os.log("PS2: Unhandled extended scancode 0x{X}\n", .{scancode});
                    return error.UnknownScancode;
                },
            };
        },
    }
}
