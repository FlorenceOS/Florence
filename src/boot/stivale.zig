pub const os = @import("../os.zig");

const paging = os.memory.paging;
const vmm    = os.memory.vmm;

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
  os.log("Stivale: Boot!\n", .{});

  info = input_info.*;
  os.log("Stivale: Boot arguments: {s}\n", .{info.cmdline});

  stivale.detect_phys_base();

  os.memory.pmm.init();
  os.platform.platform_early_init();

  for(info.memmap()) |*ent| {
    stivale.add_memmap(ent);
  }

  var context = os.vital(paging.bootstrap_kernel_paging(), "bootstrapping kernel paging");

  for(info.memmap()) |*ent| {
    stivale.map_phys(ent, &context);
  }

  const phys_high = stivale.phys_high(info.memmap());

  context.apply();
  os.memory.paging.CurrentContext = context;
  
  const heap_base = os.memory.paging.CurrentContext.phys_to_virt(phys_high);

  os.vital(vmm.init(heap_base), "initializing vmm");

  if((stivale_flags & 1) == 1) {
    os.drivers.vesa_log.register_fb(info.framebuffer_addr, info.framebuffer_pitch, info.framebuffer_width, info.framebuffer_height, info.framebuffer_bpp);
  }
  else {
    os.drivers.vga_log.register();
  }

  os.platform.acpi.register_rsdp(info.rsdp);

  os.vital(os.platform.platform_init(), "calling platform_init");

  os.kernel.kmain();
}
