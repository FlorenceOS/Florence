const kmain = @import("../kmain.zig").kmain;
const log = @import("../logger.zig").log;
const pmm = @import("../pmm.zig");
const vmm = @import("../vmm.zig");
const paging = @import("../paging.zig");
const acpi = @import("../platform/acpi.zig");
const platform = @import("../platform.zig");
const panic = @import("../panic.zig").panic;
const libalign = @import("../lib/align.zig");

const platform_init = @import("../platform.zig").platform_init;
const vesa_log = @import("../drivers/vesa_log.zig");
const vga_log = @import("../drivers/vga_log.zig");

pub const os = @import("../os/kernel.zig");

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
};

const MemmapEntry = packed struct {
  base: u64,
  length: u64,
  type: u32,
  unused: u32,
};

// Tomatboot bug: https://github.com/TomatOrg/TomatBoot-UEFI/issues/11
const high_mem_limit: u64 = 0x7f000000;

fn add_memmap_low(ent_in: *const MemmapEntry) void {
  var ent = ent_in.*;

  if(ent.type == 1) {
    if(ent.base >= high_mem_limit)
      return;

    // Don't consume anything below 2M
    if(ent.base + ent.length <= 0x200000)
      return;

    if(ent.base < 0x200000) {
      ent.length = ent.length - (0x200000 - ent.base);
      ent.base = 0x200000;
    }

    log("Consuming low: 0x{X} to 0x{X}\n", .{ent.base, ent.base + ent.length});

    if(ent.base + ent.length > high_mem_limit) {
      pmm.consume(ent.base, high_mem_limit - ent.base);
    }
    else {
      pmm.consume(ent.base, ent.length);
    }
  }
}

fn add_memmap_high(ent: *const MemmapEntry) void {
  if(ent.type == 1) {
    if(ent.base + ent.length < high_mem_limit) {
      return;
    }

    log("Consuming high: 0x{X} to 0x{X}\n", .{ent.base, ent.base + ent.length});

    if(ent.base < high_mem_limit){
      pmm.consume(high_mem_limit, ent.base + ent.length - high_mem_limit);
    }
    else {
      pmm.consume(ent.base, ent.length);
    }
  }
}

var info: StivaleInfo = undefined;

export fn stivale_main(input_info: *StivaleInfo) void {
  info = input_info.*;

  log("Loading stivale info...\n", .{});
  log("Boot arguments: {s}\n", .{info.cmdline});

  for(info.memory_map_addr[0..info.memory_map_entries]) |*ent| {
    add_memmap_low(ent);
  }

  if((stivale_flags & 1) == 1) {
    vesa_log.register_fb(info.framebuffer_addr, info.framebuffer_pitch, info.framebuffer_width, info.framebuffer_height, info.framebuffer_bpp);
  }
  else {
    vga_log.register();
  }

  const paging_root = paging.bootstrap_kernel_paging() catch |err| {
    log("Unable to bootstrap kernel paging: {}\n", .{@errorName(err)});
    panic(null, null);
  };

  log("Identity mapping bootloader data\n", .{});

  // Temporarily identity map bootloader data
  paging.map_phys(.{
    .virt = 0,
    .phys = 0,
    .size = 0x100000,
    .perm = paging.data(),
    .root = paging_root,
  }) catch |err| {
    log("Unable to map bootloader data: {}\n", .{@errorName(err)});
    panic(null, null);
  };

  for(info.memory_map_addr[0..info.memory_map_entries]) |*ent| {
    if(ent.type != 1)
      continue;

    var new_ent = ent;

    new_ent.base = libalign.align_up(u64, platform.page_sizes[0], new_ent.base);
    // If there is nothing left of the entry
    if(new_ent.base >= ent.base + ent.length)
      continue;

    // Align entry length down
    new_ent.length = libalign.align_up(u64, platform.page_sizes[0], new_ent.length);
    if(new_ent.length == 0)
      continue;

    log("Mapping phys mem 0x{X} to 0x{X}\n", .{new_ent.base, new_ent.base + new_ent.length});

    paging.add_physical_mapping(paging_root, new_ent.base, new_ent.length) catch |err| {
      log("Unable to map physical memory: {}\n", .{@errorName(err)});
      panic(null, null);
    };
  }

  paging.finalize_kernel_paging(paging_root) catch unreachable;
  asm volatile("":::"memory");
  if((stivale_flags & 1) == 1) {
    vesa_log.relocate_fb(info.framebuffer_addr);
    log("Relocated vesa_log\n", .{});
  }
  else {
    vga_log.relocate_fb();
    log("Relocated vga_log\n", .{});
  }

  log("Initializing vmm\n", .{});
  vmm.init() catch |err| {
    log("Failed to initialize vmm: {}\n", .{@errorName(err)});
    panic(null, null);
  };

  log("Registering stivale rsdp: 0x{X}\n", .{info.rsdp});
  acpi.register_rsdp(info.rsdp);

  log("Starting platform_init\n", .{});
  platform_init() catch |err| {
    log("platform_init failed: {}\n", .{@errorName(err)});
    panic(null, null);
  };

  for(info.memory_map_addr[0..info.memory_map_entries]) |*ent| {
    add_memmap_high(ent);
  }

  // Unmap bootloader data, do not touch after this
  paging.unmap(.{
    .virt = 0,
    .size = 0x100000,
    .reclaim_pages = false,
  }) catch |err| {
    log("Unable to unmap bootloader data: {}\n", .{@errorName(err)});
    panic(null, null);
  };

  log("Unmapped bootloader data\n", .{});

  kmain();
}
