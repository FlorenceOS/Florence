const os = @import("root").os;

const std = @import("std");
const lib = @import("lib");
const config = @import("config");

const log = lib.output.log.scoped(.{
    .prefix = "x86_64/ps2",
    .filter = .info,
}).write;

const apic = @import("apic.zig");
const ports = @import("ports.zig");
const eoi = @import("apic.zig").eoi;
const interrupts = @import("interrupts.zig");
const kb = lib.input.keyboard;

const Extendedness = enum {
    Extended,
    NotExtended,
};

pub var kb_interrupt_vector: u8 = undefined;
pub var kb_interrupt_gsi: ?u32 = null;
pub var mouse_interrupt_vector: u8 = undefined;
pub var mouse_interrupt_gsi: ?u32 = null;

const scancode_extended = 0xE0;

var keyboard_buffer_data: [8]u8 = undefined;
var keyboard_buffer_elements: usize = 0;

fn keyboardBuffer() []const u8 {
    return keyboard_buffer_data[0..keyboard_buffer_elements];
}

fn standardKey(ext: Extendedness, keycode: u8) void {
    defer keyboard_buffer_elements = 0;

    const loc = keyLocation(ext, keycode & 0x7F) catch return;
    kb_state.event(if (keycode & 0x80 != 0) .release else .press, loc) catch return;
}

fn finishSequence(offset: usize, seq: []const u8) bool {
    const buf = keyboardBuffer()[offset..];

    if (buf.len < seq.len)
        return false;

    if (std.mem.eql(u8, buf, seq)) {
        keyboard_buffer_elements = 0;
        return true;
    }

    // We don't have array printing yet...
    //log(.emerg, "Unexpected scancode sequence: {arr}, expected {arr}", .{ buf, seq });
    @panic("Unexpected scancode sequence!");
}

fn kbEvent() void {
    switch (keyboardBuffer()[0]) {
        0xE1 => {
            if (finishSequence(1, "\x1D\x45\xE1\x9D\xC5")) {
                kb_state.event(.press, .pause_break) catch return;
                // There is no event for releasing this key,
                // so we just gotta pretend it's released instantly
                kb_state.event(.release, .pause_break) catch return;
            }
        },
        scancode_extended => {
            if (keyboardBuffer().len < 2)
                return;

            switch (keyboardBuffer()[1]) {
                0x2A => {
                    if (finishSequence(2, &[_]u8{ scancode_extended, 0x37 })) {
                        kb_state.event(.press, .print_screen) catch return;
                    }
                },
                0xB7 => {
                    if (finishSequence(2, &[_]u8{ scancode_extended, 0xAA })) {
                        kb_state.event(.release, .print_screen) catch return;
                    }
                },
                else => {
                    standardKey(.Extended, keyboardBuffer()[1]);
                },
            }
        },
        else => {
            standardKey(.NotExtended, keyboardBuffer()[0]);
        },
    }
}

var kb_state: kb.state.KeyboardState = .{
    .layout = config.keyboard_layout,
};

fn kbHandler(_: *os.platform.InterruptFrame) void {
    keyboard_buffer_data[keyboard_buffer_elements] = ports.inb(0x60);
    keyboard_buffer_elements += 1;

    kbEvent();

    eoi();
}

fn keyLocation(ext: Extendedness, scancode: u8) !kb.keys.Location {
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
                    log(.err, "Unhandled scancode 0x{X}", .{scancode});
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
                    log(.err, "Unhandled extended scancode 0x{X}", .{scancode});
                    return error.UnknownScancode;
                },
            };
        },
    }
}

var mouse_buffer_data: [8]u8 = undefined;
var mouse_buffer_elements: usize = 0;

fn mouseEvent() void {
    if (mouse_buffer_elements == 3) {
        mouse_buffer_elements = 0;
    }
}

fn mouseHandler(_: *os.platform.InterruptFrame) void {
    mouse_buffer_data[mouse_buffer_elements] = ports.inb(0x60);
    mouse_buffer_elements += 1;

    mouseEvent();

    eoi();
}

fn canWrite() bool {
    return (ports.inb(0x64) & 2) == 0;
}

fn canRead() bool {
    return (ports.inb(0x64) & 1) != 0;
}

const max_readwrite_attempts = 10000;
const max_resend_attempts = 100;

fn write(port: u16, value: u8) !void {
    var counter: usize = 0;
    while (counter < max_readwrite_attempts) : (counter += 1) {
        if (canWrite()) {
            return ports.outb(port, value);
        }
    }

    log(.warn, "Timeout while writing to port 0x{X}!", .{port});
    return error.Timeout;
}

fn read() !u8 {
    var counter: usize = 0;
    while (counter < max_readwrite_attempts) : (counter += 1) {
        if (canRead()) {
            return ports.inb(0x60);
        }
    }

    log(.warn, "Timeout while reading!", .{});
    return error.Timeout;
}

fn getConfigByte() !u8 {
    try write(0x64, 0x20);
    return read();
}

fn writeConfigByte(config_byte_value: u8) !void {
    try write(0x64, 0x60);
    try write(0x60, config_byte_value);
}

fn disableSecondaryPort() !void {
    try write(0x64, 0xA7);
}

fn enableSecondaryPort() !void {
    try write(0x64, 0xA8);
}

fn testSecondaryPort() !bool {
    try write(0x64, 0xA9);
    return portTest();
}

fn controllerSelfTest() !bool {
    try write(0x64, 0xAA);
    return 0x55 == try read();
}

fn testPrimaryPort() !bool {
    try write(0x64, 0xAB);
    return portTest();
}

fn disablePrimaryPort() !void {
    try write(0x64, 0xAD);
}

fn enablePrimaryPort() !void {
    try write(0x64, 0xAE);
}

const Device = enum {
    primary,
    secondary,
};

fn sendCommand(device: Device, command: u8) !void {
    var resends: usize = 0;
    while (resends < max_resend_attempts) : (resends += 1) {
        if (device == .secondary) {
            try write(0x64, 0xD4);
        }
        try write(0x60, command);
        awaitAck() catch |err| {
            switch (err) {
                error.Resend => {
                    log(.debug, "Device requested command resend", .{});
                    continue;
                },
                else => return err,
            }
        };
        return;
    }

    return error.TooManyResends;
}

fn portTest() !bool {
    switch (try read()) {
        0x00 => return true, // Success
        0x01 => log(.err, "Port test failed: Clock line stuck low", .{}),
        0x02 => log(.err, "Port test failed: Clock line stuck high", .{}),
        0x03 => log(.err, "Port test failed: Data line stuck low", .{}),
        0x04 => log(.err, "Port test failed: Data line stuck high", .{}),
        else => |result| log(.err, "Port test failed: Unknown reason (0x{X})", .{result}),
    }

    return false;
}

fn awaitAck() !void {
    while (true) {
        const v = read() catch |err| {
            log(.err, "ACK read failed: {e}!", .{err});
            return err;
        };

        switch (v) {
            // ACK
            0xFA => return,

            // Resend
            0xFE => return error.Resend,

            else => log(.err, "Got a different value: 0x{X}", .{v}),
        }
    }
}

fn finalizeDevice(device: Device) !void {
    log(.debug, "Enabling interrupts", .{});
    var shift: u1 = 0;
    if (device == .secondary) shift = 1;
    try writeConfigByte((@as(u2, 1) << shift) | try getConfigByte());

    log(.debug, "Enabling scanning", .{});
    try sendCommand(device, 0xF4);
}

fn initKeyboard(irq: u8, device: Device) !bool {
    if (comptime (!config.kernel.x86_64.ps2.keyboard.enable))
        return false;

    if (kb_interrupt_gsi) |_|
        return false;

    kb_interrupt_vector = interrupts.allocate_vector();
    interrupts.add_handler(kb_interrupt_vector, kbHandler, true, 0, 1);
    kb_interrupt_gsi = apic.route_irq(0, irq, kb_interrupt_vector);

    try finalizeDevice(device);

    return true;
}

fn initMouse(irq: u8, device: Device) !bool {
    if (comptime (!config.kernel.x86_64.ps2.mouse.enable))
        return false;

    if (mouse_interrupt_gsi) |_|
        return false;

    mouse_interrupt_vector = interrupts.allocate_vector();
    interrupts.add_handler(mouse_interrupt_vector, mouseHandler, true, 0, 1);
    mouse_interrupt_gsi = apic.route_irq(0, irq, mouse_interrupt_vector);

    try finalizeDevice(device);

    return true;
}

fn initDevice(irq: u8, device: Device) !bool {
    log(.debug, "Resetting device", .{});
    try sendCommand(device, 0xFF);
    if (0xAA != try read()) {
        log(.err, "Device reset failed", .{});
        return error.DeviceResetFailed;
    }

    log(.debug, "Disabling scanning on device", .{});
    try sendCommand(device, 0xF5);

    log(.debug, "Identifying device", .{});
    try sendCommand(device, 0xF2);

    const first = read() catch |err| {
        switch (err) {
            error.Timeout => {
                log(.notice, "No identity byte, assuming keyboard", .{});
                return initKeyboard(irq, device);
            },
            else => return err,
        }
    };

    switch (first) {
        0x00 => {
            log(.info, "PS2: Standard mouse", .{});
            return initMouse(irq, device);
        },
        0x03 => {
            log(.info, "Scrollwheel mouse", .{});
            return initMouse(irq, device);
        },
        0x04 => {
            log(.info, "5-button mouse", .{});
            return initMouse(irq, device);
        },
        0xAB => {
            switch (try read()) {
                0x41, 0xC1 => {
                    log(.info, "MF2 keyboard with translation", .{});
                    return initKeyboard(irq, device);
                },
                0x83 => {
                    log(.info, "MF2 keyboard", .{});
                    return initKeyboard(irq, device);
                },
                else => |wtf| {
                    log(.warn, "Identify: Unknown byte after 0xAB: 0x{X}", .{wtf});
                },
            }
        },
        else => {
            log(.warn, "Identify: Unknown first byte: 0x{X}", .{first});
        },
    }

    return false;
}

pub fn initController() !void {
    if (comptime (!(config.kernel.x86_64.ps2.mouse.enable or config.kernel.x86_64.ps2.keyboard.enable)))
        return;

    log(.debug, "Disabling primary port", .{});
    try disablePrimaryPort();

    log(.debug, "Disabling secondary port", .{});
    try disableSecondaryPort();

    log(.debug, "Draining buffer", .{});

    // Drain buffer
    _ = ports.inb(0x60);

    log(.debug, "Setting up controller", .{});

    // Disable interrupts, enable translation
    const init_config_byte = (1 << 6) | (~@as(u8, 3) & try getConfigByte());

    try writeConfigByte(init_config_byte);

    if (!try controllerSelfTest()) {
        log(.warn, "Controller self-test failed!", .{});
        return error.FailedSelfTest;
    }

    log(.debug, "Controller self-test succeeded", .{});

    // Sometimes the config value gets reset by the self-test, so we set it again
    try writeConfigByte(init_config_byte);

    var dual_channel = ((1 << 5) & init_config_byte) != 0;

    if (dual_channel) {
        // This may be a dual channel device if the secondary clock was
        // disabled from disabling the secondary device
        try enableSecondaryPort();
        dual_channel = ((1 << 5) & try getConfigByte()) == 0;
        try disableSecondaryPort();
        if (!dual_channel) {
            log(.debug, "Not dual channel, determined late", .{});
        }
    } else {
        log(.debug, "Not dual channel, determined early", .{});
    }

    log(.info, "Detecting active ports, dual_channel = {b}", .{dual_channel});

    try enablePrimaryPort();

    if (testPrimaryPort() catch false) {
        log(.debug, "Initializing primary port", .{});
        try enablePrimaryPort();
        if (!(initDevice(1, .primary) catch false)) {
            try disablePrimaryPort();
            log(.warn, "Primary device init failed, disabled port", .{});
        }
    }

    if (dual_channel and testSecondaryPort() catch false) {
        log(.debug, "Initializing secondary port", .{});
        try enableSecondaryPort();
        if (!(initDevice(12, .secondary) catch false)) {
            try disableSecondaryPort();
            log(.warn, "Secondary device init failed, disabled port", .{});
        }
    }
}

pub fn init() void {
    initController() catch |err| {
        log(.crit, "Error while initializing: {e}", .{err});
        if (@errorReturnTrace()) |trace| {
            os.kernel.debug.dumpStackTrace(trace);
        } else {
            log(.crit, "No error trace.", .{});
        }
    };
}
