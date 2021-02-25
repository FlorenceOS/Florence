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

pub fn add_memmap(ent: *const MemmapEntry) void {
  if(ent.type != 1)
    return;

  os.log("Stivale: Consuming 0x{X} to 0x{X}\n", .{ent.base, ent.base + ent.length});
  os.memory.pmm.consume(ent.base, ent.length);
}

pub fn map_phys(ent: *const MemmapEntry, context: *platform.paging.PagingContext) void {
  if(ent.type != 1 and ent.type != 0x1000)
    return;

  var new_ent = ent.*;

  new_ent.base = libalign.align_down(u64, platform.paging.page_sizes[0], new_ent.base);
  // If there is nothing left of the entry
  if(new_ent.base >= ent.base + ent.length)
    return;

  new_ent.length = libalign.align_up(u64, platform.paging.page_sizes[0], new_ent.length);
  if(new_ent.length == 0)
    return;

  os.log("Stivale: Mapping phys mem 0x{X} to 0x{X}\n", .{new_ent.base, new_ent.base + new_ent.length});

  os.vital(paging.add_physical_mapping(.{
    .context = context,
    .phys = new_ent.base,
    .size = new_ent.length,
    .memtype = .MemoryWriteBack,
  }), "mapping physical stivale mem");
}

pub fn phys_high(map: []const MemmapEntry) usize {
  if(map.len == 0)
    @panic("No memmap!");
  const ent = map[map.len - 1];
  return ent.base + ent.length;
}

pub fn map_bootloader_data(context: *platform.paging.PagingContext) void {
  os.vital(paging.map_phys_range(0, 0x100000, paging.rw(), context), "mapping stivale bootloader data");
}
