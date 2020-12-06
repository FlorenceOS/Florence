const os = @import("root").os;
const arch = @import("builtin").arch;

const libalign = os.lib.libalign;

const paging = os.memory.paging;
const pmm    = os.memory.pmm;

const page_size = os.platform.page_sizes[0];

const Framebuffer = struct {
  x_pos: u64 = 0,
  y_pos: u64 = 0,
};

var framebuffer: ?Framebuffer = null;

pub fn register() void {
  if(arch == .x86_64) {
    const vga_size = 80 * 25 * 2;
    const vga_page_low = libalign.align_down(usize, page_size, 0xB8000);
    const vga_page_high = libalign.align_up(usize, page_size, 0xB8000 + vga_size);

    paging.map_phys_range(vga_page_low, vga_page_high, paging.wc(paging.data()), null) catch |err| {
      os.log(":/ rip couldn't map vga: {}\n", .{@errorName(err)});
      return;
    };

    framebuffer = Framebuffer{};
  }
}

fn scroll_buffer() void {
  {
    var y: u64 = 1;
    while(y < 25) {
      @memcpy(pmm.access_phys(u8, 0xB8000) + (y-1) * 80 * 2, pmm.access_phys(u8, 0xB8000) + y * 80 * 2, 80 * 2);
      y += 1;
    }
  }
  {
    var ptr = pmm.access_phys(u8, 0xB8000) + 24 * 80 * 2;
    var x: u64 = 0;
    while(x < 80) {
      ptr[0] = ' ';
      ptr[1] = 0x07;
      ptr += 2;
      x += 1;
    }
  }
}

fn feed_line() void {
  framebuffer.?.x_pos = 0;
  if(framebuffer.?.y_pos == 24) {
    scroll_buffer();
  }
  else {
    framebuffer.?.y_pos += 1;
  }
}

pub fn putch(ch: u8) void {
  if(arch == .x86_64) {
    if(framebuffer == null)
      return;

    if(ch == '\n') {
      feed_line();
      return;
    }

    if(framebuffer.?.x_pos == 80)
      feed_line();

    pmm.access_phys(u16, 0xB8000)[(framebuffer.?.y_pos * 80 + framebuffer.?.x_pos)] = 0x0700 | @as(u16, ch);
    framebuffer.?.x_pos += 1;
  }
}
