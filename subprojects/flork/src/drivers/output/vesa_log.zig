usingnamespace @import("root").preamble;

const graphics = @import("lib").graphics;

const font = config.drivers.output.vesa_log.font;
const bg = config.drivers.output.vesa_log.background;

const rendered_font = comptime graphics.font_renderer.renderBitmapFont(
    font,
    bg,
    config.drivers.output.vesa_log.foreground,
    .rgb,
);

var printer: graphics.glyph_printer.GlyphPrinter(4096, font.height) = undefined;
pub var drawTarget: ?*graphics.image_region.ImageRegion = null;

pub fn use(region: *graphics.image_region.ImageRegion) void {
    if (comptime !config.drivers.output.vesa_log.enable)
        return;

    if (drawTarget == region) {
        // Same target, do nothing
    } else if (drawTarget) |old_target| {
        printer.retarget(old_target.*, region.*, bg);
    } else {
        // First target, clear and start using
        region.fill(bg, 0, 0, region.width, region.height, true);

        // Reinitialize printer
        printer = .{};
    }

    drawTarget = region;
}

fn isPrintable(c: u8) bool {
    return font.base <= c and c < font.base + rendered_font.len;
}

comptime {
    std.debug.assert(isPrintable('?'));
}

pub fn putch(ch: u8) void {
    if (comptime !config.drivers.output.vesa_log.enable)
        return;

    if (drawTarget) |target| {
        if (ch == '\n') {
            printer.feedLine(target.*, bg);
        } else if (isPrintable(ch)) {
            printer.draw(target.*, rendered_font[ch - font.base].region(), bg);
        } else {
            printer.draw(target.*, rendered_font['?' - font.base].region(), bg);
        }
    }
}

pub fn disable() void {
    drawTarget = null;
}
