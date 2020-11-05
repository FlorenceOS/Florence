const kmain = @import("../kmain.zig").kmain;
const log = @import("../logger.zig").log;
const pmm = @import("../pmm.zig");
const vmm = @import("../vmm.zig");
const paging = @import("../paging.zig");
const acpi = @import("../platform/acpi.zig");
const platform = @import("../platform.zig");
const panic = @import("../panic.zig").panic;
const vital = @import("../vital.zig").vital;

const vesa_log = @import("../drivers/vesa_log.zig");
const vga_log = @import("../drivers/vga_log.zig");

pub const os = @import("../os/kernel.zig");

const stivale = @import("stivale_common.zig");

const MemmapEntry = stivale.MemmapEntry;

extern var stivale_flags: u16;

const StivaleInfo = packed struct {
  cmdline: [*:0]u8,
  memory_map_addr: [*]MemmapEntry,
  memory_map_entries: u64,
  framebuffer_addr: u64,
  framebuffer_pitch: u16,
  framebuffer_width: u16,
  framebuffer_height: u16,
  framebuffer_bpp: u16,
  rsdp: u64,
  module_count: u64,
  modules: u64,
  epoch: u64,
  flags: u64,

  pub fn memmap(self: *@This()) []MemmapEntry {
    return self.memory_map_addr[0..self.memory_map_entries];
  }
};

var info: StivaleInfo = undefined;

export fn stivale_main(input_info: *StivaleInfo) void {
  log("Stivale: Boot!\n", .{});

  info = input_info.*;
  log("Stivale: Boot arguments: {s}\n", .{info.cmdline});

  platform.platform_early_init();

  for(info.memmap()) |*ent| {
    stivale.add_memmap_low(ent);
  }

  const paging_root = vital(paging.bootstrap_kernel_paging(), "bootstrapping kernel paging");

  stivale.map_bootloader_data(&paging_root);

  for(info.memmap()) |*ent| {
    stivale.map_phys(ent, &paging_root);
  }

  vital(paging.finalize_kernel_paging(&paging_root), "finalizing kernel paging");

  for(info.memmap()) |*ent| {
    stivale.add_memmap_high(ent);
  }

  vital(vmm.init(stivale.phys_high(info.memmap())), "initializing vmm");

  if((stivale_flags & 1) == 1) {
    vesa_log.register_fb(info.framebuffer_addr, info.framebuffer_pitch, info.framebuffer_width, info.framebuffer_height, info.framebuffer_bpp);
  }
  else {
    vga_log.register();
  }

  acpi.register_rsdp(info.rsdp);

  kmain();
}
