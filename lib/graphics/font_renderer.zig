usingnamespace @import("root").preamble;

pub fn renderBitmapFont(
    comptime f: anytype,
    background_color: lib.graphics.color.Color,
    foreground_color: lib.graphics.color.Color,
    comptime pixel_format: lib.graphics.pixel_format.PixelFormat,
) renderedFontType(f, pixel_format) {
    var result: renderedFontType(f, pixel_format) = undefined;

    @setEvalBranchQuota(1000000);

    var byte_pos: usize = 0;

    for (result) |*c, i| {
        const region = c.regionMutable();

        region.fill(background_color, 0, 0, region.width, region.height, false);

        var y: usize = 0;
        while (y < f.height) : ({
            y += 1;
            byte_pos += 1;
        }) {
            var x: usize = 0;
            var bit: usize = 0;

            while (x < f.width) : ({
                x += 1;
            }) {
                const shift = f.width - 1 - x;
                const has_pixel_set = ((f.data[byte_pos] >> shift) & 1) != 0;
                if (has_pixel_set)
                    region.drawPixel(foreground_color, x, y, false);
            }
        }
    }

    return result;
}

fn numChars(comptime f: anytype) usize {
    const num_bytes = f.data.len;
    const bytes_per_line = @divFloor(f.width + 7, 8);
    const bytes_per_char = bytes_per_line * f.height;
    return @divExact(f.data.len, bytes_per_char);
}

fn renderedFontType(
    comptime f: anytype,
    comptime pixel_format: lib.graphics.pixel_format.PixelFormat,
) type {
    return [numChars(f)]RenderedChar(f.width, f.height, pixel_format);
}

fn RenderedChar(
    comptime width: usize,
    comptime height: usize,
    comptime pixel_format: lib.graphics.pixel_format.PixelFormat,
) type {
    return struct {
        data: [width * height * pixel_format.bytesPerPixel()]u8,

        pub fn regionMutable(self: *@This()) lib.graphics.image_region.ImageRegion {
            return .{
                .width = width,
                .height = height,
                .pixel_format = pixel_format,
                .bytes = self.data[0..],
                .pitch = width * pixel_format.bytesPerPixel(),
                .invalidateRectFunc = null,
            };
        }

        pub fn region(self: *const @This()) lib.graphics.image_region.ImageRegion {
            return .{
                .width = width,
                .height = height,
                .pixel_format = pixel_format,
                // @TODO: Remove ugly af cast
                .bytes = @intToPtr([*]u8, @ptrToInt(@as([]const u8, self.data[0..]).ptr))[0..self.data.len],
                .pitch = width * pixel_format.bytesPerPixel(),
                .invalidateRectFunc = null,
            };
        }
    };
}
