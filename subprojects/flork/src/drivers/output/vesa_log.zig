usingnamespace @import("root").preamble;

const Framebuffer = struct {
    pitch: usize,
    width: u32,
    height: u32,
    bpp: usize,

    pos_x: usize = 0,
    pos_y: usize = 0,

    yscroll: usize = 0,
    scrolling: bool = false,

    updater: Updater,
    updater_ctx: usize,

    backbuffer: []u8,
    bb_phys: usize,

    fn getWidthInChars(self: *@This()) usize {
        return self.width / font.width;
    }
    fn getHeightInChars(self: *@This()) usize {
        return self.height / font.height;
    }

    fn blitImpl(self: *@This(), comptime bpp: usize, ch: u8) void {
        @setRuntimeSafety(false);
        var y: u32 = 0;
        while (y < font.height) : (y += 1) {
            const ind = y + (@as(usize, ch) - font.base) * font.height * ((font.width + 7) / 8);
            const chr_line = font.data[ind];

            const ypx = self.pos_y * font.height + y;
            const xpx = self.pos_x * font.width;
            const bg_pixels = self.backbuffer[(self.pitch * ypx + xpx * bpp)..];

            inline for (lib.util.range.range(font.width)) |x| {
                const shift: u3 = font.width - 1 - x;
                const has_pixel_set = ((chr_line >> shift) & 1) == 1;
                if (has_pixel_set) {
                    bg_pixels[0 + x * bpp] = fgcol;
                    bg_pixels[1 + x * bpp] = fgcol;
                    bg_pixels[2 + x * bpp] = fgcol;
                } else {
                    bg_pixels[0 + x * bpp] = bgcol;
                    bg_pixels[1 + x * bpp] = bgcol;
                    bg_pixels[2 + x * bpp] = bgcol;
                }
            }
        }
        self.pos_x += 1;
    }

    fn blitChar(self: *@This(), ch: u8) void {
        switch (self.bpp) {
            4 => self.blitImpl(4, ch),
            3 => self.blitImpl(3, ch),
            else => @panic("VESAlog: Unimplemented BPP"),
        }
    }

    fn feedLine(self: *@This()) void {
        self.pos_x = 0;
        if (self.pos_y == self.getHeightInChars() - 1) {
            self.pos_y = 0;
            self.scrolling = true;
        } else {
            self.pos_y += 1;
        }
        if (self.scrolling) {
            self.yscroll += 1;
            if (self.yscroll == self.getHeightInChars()) self.yscroll = 0;
        }

        @memset(
            self.backbuffer.ptr + self.pitch * font.height * self.pos_y,
            bgcol,
            self.pitch * font.height,
        ); // clean last line
    }

    fn update(self: *@This()) void {
        @setRuntimeSafety(false);
        const yoff = self.yscroll * font.height;
        const used_h = self.getHeightInChars() * font.height;
        if (yoff > 0) {
            self.updater(
                self.backbuffer.ptr,
                0,
                used_h - yoff,
                yoff - font.height,
                self.pitch,
                self.updater_ctx,
            );
        }
        self.updater(self.backbuffer.ptr, yoff, 0, used_h - yoff, self.pitch, self.updater_ctx);
    }

    pub fn putch(self: *@This(), ch: u8) void {
        if (ch == '\n') {
            self.feedLine();
            self.update();
            return;
        }

        if (self.pos_x == framebuffer.?.getWidthInChars()) {
            self.feedLine();
        }

        self.blitChar(if (isPrintable(ch)) ch else '?');
    }
};

pub const Updater = fn (
    bb: [*]u8,
    yoff_src: usize,
    yoff_dest: usize,
    ysize: usize,
    pitch: usize,
    ctx: usize,
) void;
pub const FBInfo = struct { width: u32, height: u32 };

const font = config.font;
const bgcol = 0x20;
const fgcol = 0xbf;
const clear_screen = true;

fn isPrintable(c: u8) bool {
    return font.base <= c and c < font.base + font.data.len / 8;
}

comptime {
    std.debug.assert(isPrintable('?'));
}

pub fn lfbUpdater(
    bb: [*]u8,
    yoff_src: usize,
    yoff_dest: usize,
    ysize: usize,
    pitch: usize,
    ctx: usize,
) void {
    @setRuntimeSafety(false);
    const virt = os.memory.paging.physToWriteCombiningVirt(ctx);
    @memcpy(@intToPtr([*]u8, virt + pitch * yoff_dest), bb + pitch * yoff_src, ysize * pitch);
}

pub var framebuffer: ?Framebuffer = null;

pub fn getInfo() ?FBInfo {
    if (framebuffer) |fb| {
        var i = .{ .width = fb.width, .height = fb.height };
        return i;
    } else return null;
}

pub fn setUpdater(u: Updater, ctx: usize) void {
    if (framebuffer) |*fb| {
        fb.updater = u;
        fb.updater_ctx = ctx;
    }
}

pub fn getBackbufferPhys() usize {
    return framebuffer.?.bb_phys;
}

pub fn registerFb(
    updater: Updater,
    updater_ctx: usize,
    fb_pitch: u16,
    fb_width: u16,
    fb_height: u16,
    fb_bpp_in: u16,
) void {
    std.debug.assert(fb_bpp_in == 24 or fb_bpp_in == 32);
    const fb_bpp = fb_bpp_in / 8;
    const fb_size = @as(usize, fb_pitch) * @as(usize, fb_height);

    const bb_phys = os.memory.pmm.allocPhys(fb_size) catch |err| {
        os.log("VESAlog: Could not allocate backbuffer: {s}\n", .{@errorName(err)});
        return;
    };

    const bb_virt = os.memory.paging.kernel_context.physToWriteBackVirt(bb_phys);

    framebuffer = Framebuffer{
        .pitch = fb_pitch,
        .width = fb_width,
        .height = fb_height,
        .bpp = fb_bpp,
        .updater = updater,
        .updater_ctx = updater_ctx,
        .backbuffer = @intToPtr([*]u8, bb_virt)[0..fb_size],
        .bb_phys = bb_phys,
    };

    if (clear_screen) {
        @memset(framebuffer.?.backbuffer.ptr, bgcol, fb_size);
        os.log("VESAlog: Screen cleared.\n", .{});
    }

    os.log("VESAlog: width={}, height={}, pitch={}, bpp={}\n", .{
        fb_width,
        fb_height,
        fb_pitch,
        fb_bpp,
    });
}

pub fn putch(ch: u8) void {
    if (framebuffer) |*fb| {
        fb.putch(ch);
    }
}

pub fn disable() void {
    framebuffer = null;
}
