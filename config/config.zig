usingnamespace @import("../preamble.zig");

pub const kernel = .{
    // Build mode
    .build_mode = .ReleaseSafe,

    // Max number of CPU cores to use
    .max_cpus = 0x200,

    // True if symbols should be stripped
    .strip_symbols = false,

    // True if source blob should be created
    .build_source_blob = true,

    .x86_64 = .{
        // Allow using the `syscall` instruction to do syscalls
        .allow_syscall_instr = true,

        // The maximum number of IOAPICs to use
        .max_ioapics = 5,

        // Enable ps2 devices
        // Your system managment mode may emulate a ps2 keyboard
        // when you connect a usb keyboard. If you disable this,
        // that won't work.
        .ps2 = .{
            .enable_keyboard = true,
        },
    },

    // True if kernel should panic only once
    .panic_once = true,
};

// Terminal font
pub const font = assets.fonts.fixed_6x13;

// Default keyboard layout
pub const keyboard_layout = .en_US_QWERTY;
