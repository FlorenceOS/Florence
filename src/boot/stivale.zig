const kmain = @import("../kmain.zig").kmain;
const log = @import("../logger.zig").log;
const platform_init = @import("../platform.zig").platform_init;
const pmm = @import("../pmm.zig");
const acpi = @import("../platform/acpi.zig");

pub const os = @import("../os.zig");

const StivaleInfo = packed struct {
  cmdline: [*:0]u8,
  memory_map_addr: [*]MemmapEntry,
  memory_map_entries: u64,
  framebuffer_addr: u64,
  framebuffer_pitch: u64,
  framebuffer_width: u64,
  framebuffer_height: u64,
  framebuffer_bpp: u64,
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

fn add_memmap(ent: *const MemmapEntry) void {
  if(ent.type == 1) {
    pmm.consume(ent.base, ent.length);
  }
}

export fn stivale_main(info: *StivaleInfo) void {
  log("Loading stivale info...\n", .{});
  log("Boot arguments: {s}\n", .{info.cmdline});

  for(info.memory_map_addr[0..info.memory_map_entries]) |ent| {
    add_memmap(&ent);
  }

  platform_init() catch unreachable;
  acpi.register_rsdp(info.rsdp);
  kmain() catch unreachable;
}
