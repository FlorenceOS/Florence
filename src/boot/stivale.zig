const kmain = @import("../kmain.zig").kmain;
const log = @import("../logger.zig").log;
const pmm = @import("../pmm.zig");
const vmm = @import("../vmm.zig");
const paging = @import("../paging.zig");
const acpi = @import("../platform/acpi.zig");
const platform = @import("../platform.zig");
const panic = @import("../panic.zig").panic;

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
  info = input_info.*;

  log("Stivale: Loading info...\n", .{});
  log("Stivale: Boot arguments: {s}\n", .{info.cmdline});

  for(info.memmap()) |*ent| {
    stivale.add_memmap_low(ent);
  }

  const paging_root = paging.bootstrap_kernel_paging() catch |err| {
    log("Stivale: Unable to bootstrap kernel paging: {}\n", .{@errorName(err)});
    panic(null, null);
  };

  stivale.map_bootloader_data(paging_root);

  for(info.memmap()) |*ent| {
    stivale.map_phys(ent, paging_root);
  }

  paging.finalize_kernel_paging(paging_root) catch unreachable;

  if((stivale_flags & 1) == 1) {
    vesa_log.register_fb(info.framebuffer_addr, info.framebuffer_pitch, info.framebuffer_width, info.framebuffer_height, info.framebuffer_bpp);
  }
  else {
    vga_log.register();
  }

  log("Stivale: Initializing vmm\n", .{});
  vmm.init(stivale.phys_high(info.memmap())) catch |err| {
    log("Stivale: Failed to initialize vmm: {}\n", .{@errorName(err)});
    panic(null, null);
  };

  log("Stivale: Registering stivale rsdp: 0x{X}\n", .{info.rsdp});
  acpi.register_rsdp(info.rsdp);

  log("Stivale: Starting platform_init\n", .{});
  platform.platform_init() catch |err| {
    log("Stivale: platform_init failed: {}\n", .{@errorName(err)});
    panic(null, null);
  };

  for(info.memmap()) |*ent| {
    stivale.add_memmap_high(ent);
  }

  log("Stivale: Unmapped bootloader data\n", .{});

  kmain();
}
