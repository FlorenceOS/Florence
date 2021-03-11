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

  fn width_in_chars(self: *@This()) usize { return self.width / font.width; }
  fn height_in_chars(self: *@This()) usize { return self.height / font.height; }


  fn blit_impl(self: *@This(), comptime bpp: usize, ch: u8) void {
    @setRuntimeSafety(false);
    var y: u32 = 0; while (y < font.height) : (y += 1) {
      const chr_line = font.data[y + (@as(usize, ch) - font.base) * font.height * ((font.width + 7)/8)];

      const ypx = self.pos_y * font.height + y;
      const xpx = self.pos_x * font.width;
      const bg_pixels = self.backbuffer[(self.pitch * ypx + xpx * bpp)..];

      inline for(range(font.width)) |x| {
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

  fn blit_char(self: *@This(), ch: u8) void {
    switch (self.bpp) {
      4 => self.blit_impl(4, ch),
      3 => self.blit_impl(3, ch),
      else => @panic("VESAlog: Unimplemented BPP")
    }
  }

  fn feed_line(self: *@This()) void {
    self.pos_x = 0;
    if(self.pos_y == self.height_in_chars() - 1) {
      self.pos_y = 0;
      self.scrolling = true;
    } else {
      self.pos_y += 1;
    }
    if (self.scrolling) {
      self.yscroll += 1;
      if (self.yscroll == self.height_in_chars()) self.yscroll = 0;
    }

    @memset(self.backbuffer.ptr + self.pitch * font.height * self.pos_y, bgcol, self.pitch * font.height); // clean last line
  }

  fn update(self: *@This()) void {
    const yoff = self.yscroll * font.height;
    const used_h = self.height_in_chars() * font.height;
    if (self.yscroll > 0) self.updater(self.backbuffer.ptr, 0, used_h - yoff, yoff - font.height, self.pitch, self.updater_ctx);
    self.updater(self.backbuffer.ptr, yoff, 0, used_h - yoff, self.pitch, self.updater_ctx);
  }


  pub fn putch(self: *@This(), ch: u8) void {
    if (ch == '\n') {
      self.feed_line();
      self.update();
      return;
    }

    if (self.pos_x == framebuffer.?.width_in_chars()) self.feed_line();

    self.blit_char(if (is_printable(ch)) ch else '?');
  }
};

fn default_updater(bb: [*]u8, yoff_src: usize, yoff_dest: usize, ysize: usize, pitch: usize, ctx: usize) void {
  @memcpy(@intToPtr([*]u8, ctx + pitch * yoff_dest), bb + pitch * yoff_src, ysize * pitch);
}

pub var framebuffer: ?Framebuffer = null;

pub const Updater = fn(bb: [*]u8, yoff_src: usize, yoff_dest: usize, ysize: usize, pitch: usize, ctx: usize) void;
pub const FBInfo = struct { width: u32, height: u32 }; 

pub fn get_info() ?FBInfo {
  if (framebuffer) |fb| {
    var i = .{ .width = fb.width, .height = fb.height };
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
  
  paging.remap_phys_range(.{
    .phys = fb_page_low,
    .phys_end = fb_page_high,
    .memtype = .DeviceWriteCombining,
  }) catch |err| {
    os.log("VESAlog: Couldn't map fb: {}\n", .{@errorName(err)});
    return;
  };
  const addr = pmm.access_phys(u8, fb_phys);

  const bb_phys = os.memory.pmm.alloc_phys(fb_size) catch |err| {
    os.log("VESAlog: Could not allocate backbuffer: {}\n", .{@errorName(err)});
    return;
  };

  var size: usize = 0;
  for (os.platform.paging.page_sizes) |s| {
    if (s >= fb_size) {
      size = s;
      break;
    }
  }

  const bb_virt = os.memory.paging.kernel_context.phys_to_virt(bb_phys);
  os.memory.paging.unmap(.{ .virt = bb_virt, .size = size, .reclaim_pages = false, .context = &os.memory.paging.kernel_context });
  os.memory.paging.map_phys(.{
    .virt = bb_virt, .phys = bb_phys, .size = size,
    .perm = os.memory.paging.rw(), .memtype = .MemoryWriteBack, .context = &os.memory.paging.kernel_context,
  }) catch |err| {
    os.log("VESAlog: Could not map backbuffer: {}\n", .{@errorName(err)});
    return;
  };

  framebuffer = Framebuffer {
    .pitch = fb_pitch, .width = fb_width, .height = fb_height, .bpp = fb_bpp,
    .updater = default_updater, .updater_ctx = @ptrToInt(addr),
    .backbuffer = @intToPtr([*]u8, bb_virt)[0..fb_size], .bb_phys = bb_phys,
  };

  if(clear_screen) {
    @memset(addr, bgcol, fb_size);
    @memset(framebuffer.?.backbuffer.ptr, bgcol, fb_size);
    os.log("VESAlog: Screen cleared.\n", .{});
  }

  os.log("VESAlog: Registered fb @0x{X} with size 0x{X}\n", .{fb_phys, fb_size});
  os.log("VESAlog: width={}, height={}, pitch={}, bpp={}\n", .{fb_width, fb_height, fb_pitch, fb_bpp});
}

pub fn putch(ch: u8) void {
  if(framebuffer) |*fb| {
    fb.putch(ch);
  }
}

pub fn disable() void {
  framebuffer = null;
}
