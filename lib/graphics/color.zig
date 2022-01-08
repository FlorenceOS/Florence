const PixelFormat = @import("pixel_format.zig").PixelFormat;

pub const Color = struct {
    blue: u8,
    green: u8,
    red: u8,
    alpha: u8 = 0xFF,

    pub fn memsetAsFmt(c: @This(), comptime fmt: PixelFormat) ?u8 {
        switch (comptime fmt) {
            .rgb, .rgbx => {
                if (c.blue == c.green and c.green == c.red)
                    return c.blue;
            },
            .rgba => {
                if (c.blue == c.green and c.green == c.red and c.red == c.alpha)
                    return c.blue;
            },
        }
        return null;
    }

    pub fn readAsFmt(comptime fmt: PixelFormat, data: []u8) Color {
        return switch (comptime fmt) {
            .rgb, .rgbx => .{
                .blue = data[0],
                .green = data[1],
                .red = data[2],
            },
            .rgba => .{
                .blue = data[0],
                .green = data[1],
                .red = data[2],
                .alpha = data[3],
            },
        };
    }

    pub fn writeAsFmt(c: Color, comptime fmt: PixelFormat, data: []u8) void {
        switch (comptime fmt) {
            .rgb, .rgbx => {
                data[0] = c.blue;
                data[1] = c.green;
                data[2] = c.red;
            },
            .rgba => {
                data[0] = c.blue;
                data[1] = c.green;
                data[2] = c.red;
                data[3] = c.alpha;
            },
        }
    }
};
