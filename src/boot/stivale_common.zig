const os = @import("root").os;

const paging   = os.memory.paging;
const platform = os.platform;
const libalign = os.lib.libalign;

const std = @import("std");

pub const MemmapEntry = packed struct {
  base: u64,
  length: u64,
  type: u32,
  unused: u32,

  pub fn format(self: *const MemmapEntry, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("Base: 0x{X}, length: 0x{X}, type=0x{X}", .{self.base, self.length, self.type});
  }
};

// Tomatboot bug: https://github.com/TomatOrg/TomatBoot-UEFI/issues/11
const high_mem_limit: u64 = 0x7f000000;

pub fn add_memmap_low(ent_in: *const MemmapEntry) void {
  var ent = ent_in.*;

  if(ent.type != 1)
    return;

  if(ent.base >= high_mem_limit)
    return;

  // Don't consume anything below 2M
  if(ent.base + ent.length <= 0x200000)
    return;

  if(ent.base < 0x200000) {
    ent.length = ent.length - (0x200000 - ent.base);
    ent.base = 0x200000;
  }

  os.log("Stivale: Consuming low: 0x{X} to 0x{X}\n", .{ent.base, ent.base + ent.length});

  if(ent.base + ent.length > high_mem_limit) {
    os.memory.pmm.consume(ent.base, high_mem_limit - ent.base);
  }
  else {
    os.memory.pmm.consume(ent.base, ent.length);
  }
}

pub fn add_memmap_high(ent: *const MemmapEntry) void {
  if(ent.type != 1)
    return;

  if(ent.base + ent.length < high_mem_limit)
    return;

  os.log("Stivale: Consuming high: 0x{X} to 0x{X}\n", .{ent.base, ent.base + ent.length});

  if(ent.base < high_mem_limit){
    os.memory.pmm.consume(high_mem_limit, ent.base + ent.length - high_mem_limit);
  }
  else {
    os.memory.pmm.consume(ent.base, ent.length);
  }
}

pub fn add_memmap(ent: *const MemmapEntry) void {
  if(ent.type != 1)
    return;

  os.log("Stivale: Consuming 0x{X} to 0x{X}\n", .{ent.base, ent.base + ent.length});
  os.memory.pmm.consume(ent.base, ent.length);
}

pub fn map_phys(ent: *const MemmapEntry, paging_root: *platform.paging_root) void {
  if(ent.type != 1 and ent.type != 0x1000)
    return;

  var new_ent = ent.*;

  new_ent.base = libalign.align_down(u64, platform.page_sizes[0], new_ent.base);
  // If there is nothing left of the entry
  if(new_ent.base >= ent.base + ent.length)
    return;

  new_ent.length = libalign.align_up(u64, platform.page_sizes[0], new_ent.length);
  if(new_ent.length == 0)
    return;

  os.log("Stivale: Mapping phys mem 0x{X} to 0x{X}\n", .{new_ent.base, new_ent.base + new_ent.length});

  os.vital(paging.add_physical_mapping(paging_root, new_ent.base, new_ent.length), "mapping physical stivale mem");
}

pub fn phys_high(map: []const MemmapEntry) usize {
  if(map.len == 0)
    @panic("No memmap!");
  const ent = map[map.len - 1];
  return ent.base + ent.length;
}

pub fn map_bootloader_data(paging_root: *platform.paging_root) void {
  os.vital(paging.map_phys_range(0, 0x100000, paging.data(), paging_root), "mapping stivale bootloader data");
}
