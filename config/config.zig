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
            .keyboard = .{
                .enable = true,
            },

            .mouse = .{
                .enable = true,
            },
        },

        // VMWARE integration for things like absolute cursor position.
        // This is also implemented in other virtualization software
        // like QEMU.
        .vmware = .{
            .enable = true,

            .abscursor = true,
        },

        // Port E9 debug logging
        .e9 = .{
            .enable = true,
        },

        .serial = .{
            .enabled_ports = [_]comptime_int{
                //1,
                //2,
                //3,
                //4,
            },
        },
    },

    // True if kernel should panic only once
    .panic_once = true,

    // If true, runs kepler tests after system initialization
    .run_kepler_tests = true,

    .pci = .{
        // Toggle for PCI bus enumeration and device discovery
        .enable = true,
    },
};

pub const copernicus = .{
    // Build mode
    .build_mode = .Debug,

    // True if symbols should be stripped
    .strip_symbols = false,

    // True if source blob should be created
    .build_source_blob = true,
};

pub const drivers = .{
    .block = .{
        .ahci = .{
            .enable = true,
        },
        .nvme = .{
            .enable = true,
        },
    },

    .gpu = .{
        .virtio_gpu = .{
            .enable = true,

            .default_resolution = .{
                .width = 1280,
                .height = 720,
            },
        },
    },

    .misc = .{},

    .net = .{
        .e1000 = .{
            .enable = true,
        },
    },

    .output = .{
        .vesa_log = .{
            .enable = true,

            .font = assets.fonts.fixed_6x13,
            .background = .{
                .red = 0x20,
                .green = 0x20,
                .blue = 0x20,
            },
            .foreground = .{
                .red = 0xbf,
                .green = 0xbf,
                .blue = 0xbf,
            },
        },

        .vga_log = .{
            .enable = true,
        },
    },

    .usb = .{
        .xhci = .{
            .enable = true,
        },
    },
};

// Default keyboard layout
pub const keyboard_layout = .en_US_QWERTY;
