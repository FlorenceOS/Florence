usingnamespace @import("root").preamble;

const ImageRegion = lib.graphics.image_region.ImageRegion;
const ScrollingRegion = lib.graphics.scrolling_region.ScrollingRegion;
const PixelFormat = lib.graphics.pixel_format.PixelFormat;
const Color = lib.graphics.color.Color;

pub fn GlyphPrinter(comptime max_width: usize, comptime glyph_height: usize) type {
    return struct {
        buffer_data: [max_width * glyph_height * 4]u8 = undefined,
        used_width: usize = 0,
        scroller: ScrollingRegion = .{},

        pub fn buffer(self: *@This(), width_to_add: usize, pixel_format: PixelFormat) ImageRegion {
            self.used_width += width_to_add;
            return .{
                .bytes = self.buffer_data[0..],
                .width = self.used_width,
                .height = glyph_height,
                .pitch = max_width * 4,
                .pixel_format = pixel_format,
                .invalidateRectFunc = null,
            };
        }

        pub fn flush(self: *@This(), into: ImageRegion, bg: Color) void {
            if (self.used_width != 0)
                self.feedLine(into, bg);
        }

        pub fn feedLine(self: *@This(), into: ImageRegion, bg: Color) void {
            const old_width = self.used_width;
            if (self.used_width < into.width) {
                self.buffer(
                    into.width - self.used_width,
                    into.pixel_format,
                ).fill(
                    bg,
                    old_width,
                    0,
                    into.width - old_width,
                    glyph_height,
                    false,
                );
            }
            self.scroller.putBottom(self.buffer(0, into.pixel_format), into, old_width);
            self.used_width = 0;
        }

        pub fn draw(self: *@This(), into: ImageRegion, glyph: ImageRegion, bg: Color) void {
            // If we can't fit the glyph, feed line
            if (glyph.width + self.used_width > into.width) {
                self.feedLine(into, bg);
            }

            // Put the glyph into the buffer
            self.buffer(glyph.width, into.pixel_format).drawImage(
                glyph,
                self.used_width - glyph.width,
                0,
                false,
            );
        }

        pub fn retarget(self: *@This(), old: ImageRegion, new: ImageRegion, bg: Color) void {
            if (new.width < old.width) {
                // If we're making the buffer smaller, we have to flush the printer first.
                self.flush(old, bg);
            }

            self.scroller.retarget(old, new, bg);
        }
    };
}
