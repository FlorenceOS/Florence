pub const fixed_6x13 = .{
    .width = 6,
    .height = 13,
    .base = 0x20,
    .data = @embedFile("fixed6x13.bin"),
};

pub const fixed_8x13 = .{
    .width = 8,
    .height = 13,
    .base = 0x20,
    .data = @embedFile("fixed8x13.bin"),
};

pub const vesa_font = .{
    .width = 8,
    .height = 8,
    .base = 0x20,
    .data = @embedFile("vesa_font.bin"),
};
