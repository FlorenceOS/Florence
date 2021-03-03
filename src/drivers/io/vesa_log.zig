const os = @import("root").os;
const std = @import("std");

const range = os.lib.range.range;

const page_size = os.platform.paging.page_sizes[0];

const paging = os.memory.paging;
const pmm    = os.memory.pmm;

const font_fixed_6x13 = .{
  .width = 6,
  .height = 13,
  .base = 0x20,
  .data = @embedFile("fixed6x13.bin"),
};

const font_fixed_8x13 = .{
  .width = 8,
  .height = 13,
  .base = 0x20,
  .data = @embedFile("fixed8x13.bin"),
};

const vesa_font = .{
  .width = 8,
  .height = 8,
  .base = 0x20,
  .data = @embedFile("vesa_font.bin"),
};

const font = font_fixed_6x13;

comptime {
  std.debug.assert(is_printable('?'));
}

fn is_printable(c: u8) bool {
  return font.base <= c and c < font.base + font.data.len/8;
}

const bgcol = 0x20;
const fgcol = 0xbf;

const clear_screen = true;

const Framebuffer = struct {
  addr: []u8,
  pitch: usize,
  width: u32,
  height: u32,
  bpp: usize,

  pos_x: usize = 0,
  pos_y: usize = 0,

  phys: usize,

  updater: Updater,
  updater_ctx: usize,

  backbuffer: []u8,

  fn width_in_chars(self: *@This()) usize {
    return self.width / font.width;
  }

  fn height_in_chars(self: *@This()) usize {
    return self.height / font.height;
  }

  fn offset(self: *@This(), comptime bpp: usize, x: usize, y: usize) usize {
    return self.pitch * y + x * bpp;
  }

  fn px(self: *@This(), comptime bpp: usize, x: usize, y: usize) *[3]u8 {
    const off = self.offset(bpp, x, y);
    return self.addr[off .. off + 3][0 .. 3];
  }

  fn back_px(self: *@This(), comptime bpp: usize, x: usize, y: usize) *[3]u8 {
    const off = self.offset(bpp, x, y);
    return self.backbuffer[off .. off + 3][0 .. 3];
  }

  fn blit_impl(self: *@This(), comptime bpp: usize, ch: u8) void {
    @setRuntimeSafety(false);
    inline for(range(font.height)) |y| {
      const chr_line = font.data[y + (@as(usize, ch) - font.base) * font.height * ((font.width + 7)/8)];

      const ypx = self.pos_y * font.height + y;

      inline for(range(font.width)) |x| {
        const xpx = self.pos_x * font.width + x;

        const pixel = self.px(bpp, xpx, ypx);
        const bg_pixel = self.back_px(bpp, xpx, ypx);

        const shift: u3 = font.width - 1 - x;
        const has_pixel_set = ((chr_line >> shift) & 1) == 1;

        if(has_pixel_set) {
          bg_pixel[0] = fgcol;
          bg_pixel[1] = fgcol;
          bg_pixel[2] = fgcol;
        }
        else {
          bg_pixel[0] = bgcol;
          bg_pixel[1] = bgcol;
          bg_pixel[2] = bgcol;
        }
      }
    }
    self.pos_x += 1;
  }

  fn blit_char(self: *@This(), ch: u8) void {
    if(self.bpp == 4) {
      self.blit_impl(4, ch);
      return;
    }
    if(self.bpp == 3) {
      self.blit_impl(3, ch);
      return;
    }
    @panic("Unimplemented BPP");
  }

  fn scroll_fb(self: *@This()) void {
    @setRuntimeSafety(false);
    var y: usize = font.height;
    while(y < (self.height/font.height) * font.height): (y += 1) {
      const dst = self.backbuffer.ptr + self.pitch * (y - font.height);
      const src = self.backbuffer.ptr + self.pitch * y;
      @memcpy(dst, src, self.pitch);
    }
    @memset(self.backbuffer.ptr + self.pitch * (y - font.height), bgcol, self.pitch * font.height);
    self.updater(0, 0, self.width, self.height, self.updater_ctx);
  }

  fn feed_line(self: *@This()) void {
    self.pos_x = 0;
    if(self.pos_y == self.height_in_chars() - 1) {
      self.scroll_fb();
    }
    else {
      self.pos_y += 1;
    }
  }

  fn update(self: *@This()) void {
    var y = @truncate(u32, self.pos_y * font.height);
    self.updater(0, y, self.width, @truncate(u32, font.height), self.updater_ctx);
  }

  fn flush_backbuffer(self: *@This()) void {
    @memcpy(self.addr.ptr, self.backbuffer.ptr, self.pitch * self.height);
  }

  pub fn putch(self: *@This(), ch: u8) void {
    if(ch == '\n') {
      self.update();
      self.feed_line();
      self.flush_backbuffer();
      return;
    }

    if(self.pos_x == framebuffer.?.width_in_chars())
      self.feed_line();

    if(!is_printable(ch)) {
      self.blit_char('?');
    }
    else {
      self.blit_char(ch);
    }
  }
};

fn default_updater(x: u32, y: u32, w: u32, h: u32, ctx: usize) void {} // Do nothing

var framebuffer: ?Framebuffer = null;

pub const Updater = fn(x: u32, y: u32, width: u32, height: u32, ctx: usize)void;
pub const FBInfo = struct { phys: usize, width: u32, height: u32 }; 

pub fn get_info() ?FBInfo {
  if (framebuffer) |fb| {
    var i = .{ .phys = fb.phys, .width = fb.width, .height = fb.height };
    return i;
  } else return null;
}

pub fn set_updater(u: Updater, ctx: usize) void {
  if (framebuffer) |*fb| {
    fb.updater = u;
    fb.updater_ctx = ctx;
  }
}

pub fn register_fb(fb_phys: usize, fb_pitch: u16, fb_width: u16, fb_height: u16, fb_bpp_in: u16) void {
  std.debug.assert(fb_bpp_in == 24 or fb_bpp_in == 32);
  // Bits are lies, I do bytes.
  const fb_bpp = fb_bpp_in / 8;
  const fb_size = @as(usize, fb_pitch) * @as(usize, fb_height);
  const fb_page_low = os.lib.libalign.align_down(usize, page_size, fb_phys);
  const fb_page_high = os.lib.libalign.align_up(usize, page_size, fb_phys + fb_size);

  // Allocate backbuffer
  const backbuffer = os.memory.vmm.backed(.Eternal).alloc(u8, fb_size) catch |err| {
    os.log("VESAlog: Couldn't map fb: {}\n", .{@errorName(err)});
    return;
  };

  paging.remap_phys_range(.{
    .phys = fb_page_low,
    .phys_end = fb_page_high,
    .memtype = .DeviceWriteCombining,
  }) catch |err| {
    os.log("VESAlog: Couldn't map fb: {}\n", .{@errorName(err)});
    // Backbuffer is leaked =(
    return;
  };

  framebuffer = Framebuffer {
    .addr = pmm.access_phys(u8, fb_phys)[0..fb_size],
    .pitch = fb_pitch,
    .width = fb_width,
    .height = fb_height,
    .bpp = fb_bpp,
    .phys = fb_phys,
    .updater = default_updater,
    .updater_ctx = 0,
    .backbuffer = backbuffer,
  };

  if(clear_screen) {
    @memset(framebuffer.?.addr.ptr, bgcol, fb_size);
    @memset(framebuffer.?.backbuffer.ptr, bgcol, fb_size);
    os.log("VESAlog: Screen cleared.\n", .{});
  }

  os.log("VESAlog: Registered fb @0x{X} with size 0x{X}\n", .{fb_phys, fb_size});
  os.log("VESAlog:  Width:  {}\n", .{fb_width});
  os.log("VESAlog:  Height: {}\n", .{fb_height});
  os.log("VESAlog:  Pitch:  {}\n", .{fb_pitch});
  os.log("VESAlog:  BPP:    {}\n", .{fb_bpp});
}

pub fn putch(ch: u8) void {
  if(framebuffer) |*fb| {
    fb.putch(ch);
  }
}

pub fn disable() void {
  framebuffer = null;
}
