const os = @import("root").os;
const std = @import("std");

const range = os.lib.range.range;

const page_size = os.platform.page_sizes[0];

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

const bgcol = 0x00;
const fgcol = 0xaa;

const clear_screen = false;


const Framebuffer = struct {
  addr: []u8,
  pitch: u64,
  width: u32,
  height: u32,
  bpp: u64,

  pos_x: u64 = 0,
  pos_y: u64 = 0,

  phys: u64,

  updater: Updater,
  updater_ctx: u64,

  pub fn width_in_chars(self: *@This()) u64 {
    return self.width / font.width;
  }

  pub fn height_in_chars(self: *@This()) u64 {
    return self.height / font.height;
  }
};

fn default_updater(x: u32, y: u32, w: u32, h: u32, ctx: u64) void {} // Do nothing

var framebuffer: ?Framebuffer = null;

pub const Updater = fn(x: u32, y: u32, width: u32, height: u32, ctx: u64)void;
pub const FBInfo = struct { phys: u64, width: u32, height: u32 }; 

pub fn get_info() ?FBInfo {
  if (framebuffer) |fb| {
    var i = .{ .phys = fb.phys, .width = fb.width, .height = fb.height };
    return i;
  } else return null;
}

pub fn set_updater(u: Updater, ctx: u64) void {
  if (framebuffer) |*fb| {
    fb.updater = u;
    fb.updater_ctx = ctx;
  }
}

fn is_printable(c: u8) bool {
  return font.base <= c and c < font.base + font.data.len/8;
}

pub fn register_fb(fb_phys: usize, fb_pitch: u16, fb_width: u16, fb_height: u16, fb_bpp_in: u16) void {
  std.debug.assert(fb_bpp_in == 24 or fb_bpp_in == 32);
  // Bits are lies, I do bytes.
  const fb_bpp = fb_bpp_in / 8;
  const fb_size = @as(u64, fb_pitch) * @as(u64, fb_height);
  const fb_page_low = os.lib.libalign.align_down(usize, page_size, fb_phys);
  const fb_page_high = os.lib.libalign.align_up(usize, page_size, fb_phys + fb_size);

  paging.remap_phys_range(.{
    .phys = fb_page_low,
    .phys_end = fb_page_high,
    .memtype = .DeviceWriteCombining,
  }) catch |err| {
    os.log("VESAlog: Couldn't map fb: {}\n", .{@errorName(err)});
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
  };

  if(clear_screen) {
    @memset(@ptrCast([*]u8, framebuffer.?.addr), bgcol, fb_size);
    os.log("VESAlog: Screen cleared.\n", .{});
  }

  os.log("VESAlog: Registered fb @0x{X} with size 0x{X}\n", .{fb_phys, fb_size});
  os.log("VESAlog:  Width:  {}\n", .{fb_width});
  os.log("VESAlog:  Height: {}\n", .{fb_height});
  os.log("VESAlog:  Pitch:  {}\n", .{fb_pitch});
  os.log("VESAlog:  BPP:    {}\n", .{fb_bpp});
}

fn px(comptime bpp: u64, x: u64, y: u64) *[3]u8 {
  const offset = framebuffer.?.pitch * y + x * bpp;
  return framebuffer.?.addr[offset .. offset + 3][0..3];
}

fn blit_impl(comptime bpp: u64, ch: u8) void {
  inline for(range(font.height)) |y| {
    const chr_line = font.data[y + (@as(u64, ch) - font.base) * font.height * ((font.width + 7)/8)];

    const ypx = framebuffer.?.pos_y * font.height + y;

    inline for(range(font.width)) |x| {
      const xpx = framebuffer.?.pos_x * font.width + x;

      const pixel = px(bpp, xpx, ypx);

      const shift: u3 = font.width - 1 - x;
      const has_pixel_set = ((chr_line >> shift) & 1) == 1;

      if(has_pixel_set) {
        pixel[0] = fgcol;
        pixel[1] = fgcol;
        pixel[2] = fgcol;
      }
      else {
        pixel[0] = bgcol;
        pixel[1] = bgcol;
        pixel[2] = bgcol;
      }
    }
  }
  framebuffer.?.pos_x += 1;
}

fn blit_char(ch: u8) void {
  if(framebuffer.?.bpp == 4) {
    blit_impl(4, ch);
    return;
  }
  if(framebuffer.?.bpp == 3) {
    blit_impl(3, ch);
    return;
  }
  unreachable;
}

fn scroll_fb() void {
  // Speeds this up by like 8x, and I don't think there are bugs here
  @setRuntimeSafety(false);

  // Yes this is slow but I don't care, I love it.
  var y: u64 = font.height;
  while(y < (framebuffer.?.height/font.height) * font.height): (y += 1) {
    const dst = @ptrCast([*]u8, framebuffer.?.addr) + framebuffer.?.pitch * (y - font.height);
    const src = @ptrCast([*]u8, framebuffer.?.addr) + framebuffer.?.pitch * y;
    @memcpy(dst, src, framebuffer.?.pitch);
  }
  @memset(@ptrCast([*]u8, framebuffer.?.addr) + framebuffer.?.pitch * (y - font.height), 0x00, framebuffer.?.pitch * font.height);
  framebuffer.?.updater(0, 0, framebuffer.?.width, framebuffer.?.height, framebuffer.?.updater_ctx);
}

fn feed_line() void {
  framebuffer.?.pos_x = 0;
  if(framebuffer.?.pos_y == framebuffer.?.height_in_chars() - 1) {
    scroll_fb();
  }
  else {
    framebuffer.?.pos_y += 1;
  }
}

pub fn update() void {
  var y = @truncate(u32, framebuffer.?.pos_y * font.height);
  framebuffer.?.updater(0, y, framebuffer.?.width, @truncate(u32, font.height), framebuffer.?.updater_ctx);
}

pub fn putch(ch: u8) void {
  if(framebuffer != null) {
    if(ch == '\n') {
      update();
      feed_line();
      return;
    }

    if(framebuffer.?.pos_x == framebuffer.?.width_in_chars())
      feed_line();

    if(!is_printable(ch)) {
      std.debug.assert(is_printable('?'));
      blit_char('?');
    }
    else {
      blit_char(ch);
    }
  }
}

pub fn disable() void {
  framebuffer = null;
}
