usingnamespace @import("root").preamble;

const PixelFormat = lib.graphics.pixel_format.PixelFormat;
const Color = lib.graphics.color.Color;

pub const InvalidateRectFunc = fn (r: *ImageRegion, x: usize, y: usize, width: usize, height: usize) void;

pub const ImageRegion = struct {
    width: usize,
    height: usize,
    pixel_format: PixelFormat,
    bytes: []u8,
    pitch: usize,
    /// Function to call when a subregion of the image has been modified
    invalidateRectFunc: ?InvalidateRectFunc,

    // The following variables are managed by this struct and shouldn't be changed

    /// If the image is a less wide subregion() of any other ImageRegion
    /// means that the bytes between bpp*width and pitch can't be overwritten
    full_width: bool = true,

    // Offsets are needed for the invalidation callbacks for subregions
    x_offset: usize = 0,
    y_offset: usize = 0,

    pub fn subregion(
        self: *const @This(),
        x: usize,
        y: usize,
        width: usize,
        height: usize,
    ) @This() {
        if (x + width > self.width) unreachable;
        if (y + height > self.height) unreachable;

        return .{
            .width = width,
            .height = height,
            .pixel_format = self.pixel_format,

            .bytes = self.startingAt(x, y),
            .pitch = self.pitch,
            .invalidateRectFunc = self.invalidateRectFunc,

            .full_width = self.full_width and width == self.width,
            .x_offset = self.x_offset + x,
            .y_offset = self.y_offset + y,
        };
    }

    pub fn invalidateRect(
        self: *const @This(),
        x: usize,
        y: usize,
        width: usize,
        height: usize,
    ) void {
        if (x + width > self.width) unreachable;
        if (y + height > self.height) unreachable;

        if (self.invalidateRectFunc) |func|
            func(@intToPtr(*@This(), @ptrToInt(self)), x + self.x_offset, y + self.y_offset, width, height);
    }

    /// Draw a pixel to the region
    pub fn drawPixel(
        self: *const @This(),
        c: Color,
        x: usize,
        y: usize,
        comptime invalidate: bool,
    ) void {
        switch (self.pixel_format) {
            .rgb => self.drawPixelWithFormat(.rgb, c, x, y, invalidate),
            .rgba => self.drawPixelWithFormat(.rgba, c, x, y, invalidate),
            .rgbx => self.drawPixelWithFormat(.rgbx, c, x, y, invalidate),
        }
    }

    /// Draw a pixel, assuming the target format
    pub fn drawPixelWithFormat(
        self: *const @This(),
        comptime fmt: PixelFormat,
        c: Color,
        x: usize,
        y: usize,
        comptime invalidate: bool,
    ) void {
        if (x > self.width) unreachable;
        if (y > self.height) unreachable;
        if (fmt != self.pixel_format) unreachable;

        c.writeAsFmt(fmt, self.startingAt(x, y));

        if (comptime invalidate)
            self.invalidateRect(x, y, 1, 1);
    }

    pub fn getPixel(
        self: *const @This(),
        x: usize,
        y: usize,
    ) Color {
        return switch (self.pixel_format) {
            .rgb => self.getPixelWithFormat(.rgb, x, y),
            .rgba => self.getPixelWithFormat(.rgba, x, y),
            .rgbx => self.getPixelWithFormat(.rgbx, x, y),
        };
    }

    pub fn getPixelWithFormat(self: *const @This(), comptime fmt: PixelFormat, x: usize, y: usize) Color {
        if (x > self.width) unreachable;
        if (y > self.height) unreachable;
        if (fmt != self.pixel_format) unreachable;

        return readAsFmt(fmt, startingAt(x, y));
    }

    pub fn fill(
        self: *const @This(),
        c: Color,
        x: usize,
        y: usize,
        width: usize,
        height: usize,
        comptime invalidate: bool,
    ) void {
        switch (self.pixel_format) {
            .rgb => self.fillWithFormat(.rgb, c, x, y, width, height, invalidate),
            .rgba => self.fillWithFormat(.rgba, c, x, y, width, height, invalidate),
            .rgbx => self.fillWithFormat(.rgbx, c, x, y, width, height, invalidate),
        }
    }

    pub fn fillWithFormat(
        target: *const @This(),
        comptime fmt: PixelFormat,
        c: Color,
        x: usize,
        y: usize,
        width: usize,
        height: usize,
        comptime invalidate: bool,
    ) void {
        if (!target.pixel_format.canWrite(fmt)) unreachable;

        if (width + x > target.width) unreachable;
        if (height + y > target.height) unreachable;

        // Can we memset (all bytes equal) when filing?
        if (c.memsetAsFmt(fmt)) |byte_value| {
            if (x == 0 and width == target.width and target.full_width) {
                lib.util.libalign.alignedFill(u32, target.startingAt(0, y)[0 .. height * target.pitch], byte_value);
            } else {
                var curr_y: usize = 0;
                var target_lines = target.startingAt(x, y);
                while (true) {
                    const line = target_lines[0 .. width * comptime fmt.bytesPerPixel()];
                    lib.util.libalign.alignedFill(u32, line, byte_value);

                    curr_y += 1;

                    if (curr_y == height)
                        break;

                    target_lines = target_lines[target.pitch..];
                }
            }
        } else {
            var pixel_bytes: [fmt.meaningfulBytesPerPixel()]u8 = undefined;
            c.writeAsFmt(fmt, &pixel_bytes);

            var curr_y: usize = 0;
            var target_lines = target.startingAt(x, y);
            while (true) {
                var curr_x: usize = 0;
                var target_pixels = target_lines;
                while (true) {
                    lib.util.libalign.alignedCopy(u8, target_pixels, pixel_bytes[0..]);

                    curr_x += 1;

                    if (curr_x == width)
                        break;

                    target_pixels = target_pixels[comptime fmt.bytesPerPixel()..];
                }

                curr_y += 1;

                if (curr_y == height)
                    break;

                target_lines = target_lines[target.pitch..];
            }
        }

        if (comptime invalidate)
            target.invalidateRect(x, y, width, height);
    }

    /// Assume both source and target formats
    pub fn drawImageWithFmt(
        target: *const @This(),
        comptime source_fmt: PixelFormat,
        comptime target_fmt: PixelFormat,
        source: ImageRegion,
        x: usize,
        y: usize,
        comptime invalidate: bool,
    ) void {
        // Check if the formats we're using are valid
        if (!source.pixel_format.canReadManyAs(source_fmt)) unreachable;
        if (!target.pixel_format.canWriteMany(target_fmt)) unreachable;

        // Bounds checks
        if (source.width + x > target.width) unreachable;
        if (source.height + y > target.height) unreachable;

        // Check if the input and output formats are bit-compatible
        if (comptime target_fmt.canWriteMany(source_fmt)) {
            // Can we copy the entire thing in one memcpy?
            if (source.pitch == target.pitch and source.full_width and target.full_width) {
                const num_bytes = source.pitch * source.height;
                lib.util.libalign.alignedCopy(u32, target.startingAt(x, y), source.bytes);
            } else {
                const num_bytes = source.width * comptime source_fmt.bytesPerPixel();
                var source_bytes = source.bytes;
                var target_bytes = target.startingAt(x, y);
                var source_y: usize = 0;
                while (true) {
                    lib.util.libalign.alignedCopy(u32, target_bytes, source_bytes[0..num_bytes]);

                    source_y += 1;

                    if (source_y == source.height)
                        break;

                    target_bytes = target_bytes[target.pitch..];
                    source_bytes = source_bytes[source.pitch..];
                }
            }
        }
        // Fine, do one pixel at a time
        else {
            var source_lines = source.bytes;
            var target_lines = target.startingAt(x, y);

            var source_y: usize = 0;
            while (true) {
                var source_x: usize = 0;
                var source_pixels = source_lines;
                var target_pixels = target_lines;
                while (true) {
                    if (comptime target_fmt.canWrite(source_fmt)) {
                        const source_bytes = source_fmt.meaningfulBytesPerPixel();
                        const target_bytes = target_fmt.meaningfulBytesPerPixel();
                        const bytes_to_copy = std.math.min(source_bytes, target_bytes);
                        lib.util.libalign.alignedCopy(u32, target_pixels, source_pixels[0..comptime bytes_to_copy]);
                    } else {
                        lib.graphics.color.Color.readAsFmt(
                            source_fmt,
                            source_pixels,
                        ).writeAsFmt(
                            target_fmt,
                            target_pixels,
                        );
                    }

                    source_x += 1;

                    if (source_x == source.width)
                        break;

                    source_pixels = source_pixels[comptime source_fmt.bytesPerPixel()..];
                    target_pixels = target_pixels[comptime target_fmt.bytesPerPixel()..];
                }

                source_y += 1;
                if (source_y == source.height)
                    break;

                source_lines = source_lines[source.pitch..];
                target_lines = target_lines[target.pitch..];
            }
        }

        if (comptime invalidate)
            target.invalidateRect(x, y, source.width, source.height);
    }

    // I wish I could use https://github.com/ziglang/zig/issues/7224 right now...

    /// Assume the sourcce format
    pub fn drawImageWithSourceFmt(
        self: *const @This(),
        comptime source_fmt: PixelFormat,
        source: ImageRegion,
        x: usize,
        y: usize,
        comptime invalidate: bool,
    ) void {
        switch (self.pixel_format) {
            .rgb => self.drawImageWithFmt(source_fmt, .rgb, source, x, y, invalidate),
            .rgba => self.drawImageWithFmt(source_fmt, .rgba, source, x, y, invalidate),
            .rgbx => self.drawImageWithFmt(source_fmt, .rgbx, source, x, y, invalidate),
        }
    }

    /// Assume the target format
    pub fn drawImageWithTargetFmt(
        self: *const @This(),
        comptime target_fmt: PixelFormat,
        source: ImageRegion,
        x: usize,
        y: usize,
        comptime invalidate: bool,
    ) void {
        switch (source.pixel_format) {
            .rgb => self.drawImageWithFmt(.rgb, target_fmt, source, x, y, invalidate),
            .rgba => self.drawImageWithFmt(.rgba, target_fmt, source, x, y, invalidate),
            .rgbx => self.drawImageWithFmt(.rgbx, target_fmt, source, x, y, invalidate),
        }
    }

    /// Assume the source and target pixel formats are equal
    pub fn drawImageSameFmt(
        self: *const @This(),
        source: ImageRegion,
        x: usize,
        y: usize,
        comptime invalidate: bool,
    ) void {
        switch (self.pixel_format) {
            .rgb => self.drawImageWithFmt(.rgb, .rgb, source, x, y, invalidate),
            .rgba => self.drawImageWithFmt(.rgba, .rgba, source, x, y, invalidate),
            .rgbx => self.drawImageWithFmt(.rgbx, .rgbx, source, x, y, invalidate),
        }
    }

    /// Draw the source image region to the target one
    pub fn drawImage(
        self: *const @This(),
        source: ImageRegion,
        x: usize,
        y: usize,
        comptime invalidate: bool,
    ) void {
        switch (self.pixel_format) {
            .rgb => self.drawImageWithTargetFmt(.rgb, source, x, y, invalidate),
            .rgba => self.drawImageWithTargetFmt(.rgba, source, x, y, invalidate),
            .rgbx => self.drawImageWithTargetFmt(.rgbx, source, x, y, invalidate),
        }
    }

    fn startingAt(self: *const @This(), x: usize, y: usize) []u8 {
        if (x > self.width) unreachable;
        if (y > self.height) unreachable;

        const offset = self.pixel_format.bytesPerPixel() * x + self.pitch * y;

        return self.bytes[offset..];
    }
};
