const platform = @import("platform.zig");
const log = @import("logger.zig").log;
const libalign = @import("lib/align.zig");
const range = @import("lib/range.zig").range;
const range_reverse = @import("lib/range.zig").range_reverse;
const pmm = @import("pmm.zig");

pub const make_page_table = platform.make_page_table;
const page_table_entry = platform.page_table_entry;
const page_table = platform.page_table;
const page_sizes = platform.page_sizes;
const paging_levels = page_sizes.len;
const index_into_table = platform.index_into_table;

pub const map_args = struct {
  virt: usize,
  size: usize,
  perm: perms,
  root: ?u64 = null,
};

pub fn map(args: map_args) !void {
  var argc = args;
  return map_loop(&argc.virt, null, &argc.size, argc.root, argc.perm);
}

pub const map_phys_args = struct {
  virt: usize,
  phys: usize,
  size: usize,
  perm: perms,
  root: ?u64 = null,
};

pub fn map_phys(args: map_phys_args) !void {
  var argc = args;
  return map_loop(&argc.virt, &argc.phys, &argc.size, argc.root, argc.perm);
}

pub const unmap_args = struct {
  virt: usize,
  size: usize,
  reclaim_pages: bool,
  root: ?u64 = null,
};

pub fn unmap(args: unmap_args) !void {
  var argc = args;
  try unmap_impl(&argc.virt, &argc.size, argc.reclaim_pages, argc.root);
}

pub const perms = struct {
  writable: bool,
  executable: bool,
  user: bool,
  cacheable: bool,
  writethrough: bool,
};

pub fn mmio() perms {
  return perms {
    .writable = true,
    .executable = false,
    .user = false,
    .cacheable = false,
    .writethrough = true,
  };
}

pub fn code() perms {
  return perms {
    .writable = false,
    .executable = true,
    .user = false,
    .cacheable = true,
    .writethrough = true,
  };
}

pub fn rodata() perms {
  return perms {
    .writable = false,
    .executable = false,
    .user = false,
    .cacheable = true,
    .writethrough = true,
  };
}

pub fn data() perms {
  return perms {
    .writable = true,
    .executable = false,
    .user = false,
    .cacheable = true,
    .writethrough = true,
  };
}

pub fn rwx() perms {
  return perms {
    .writable = true,
    .executable = true,
    .user = false,
    .cacheable = true,
    .writethrough = true,
  };
}

pub fn wc(curr: perms) perms {
  var ret = curr;
  ret.writethrough = true;
  return ret;
}

pub fn user(p: perms) perms {
  var ret = curr;
  ret.writethrough = true;
  return ret;
}

pub fn get_current_paging_root() u64 {
  return platform.current_paging_root();
}

pub fn set_paging_root(pt_phys: u64, phys_base: u64) !void {
  platform.set_paging_root(pt_phys);
  pmm.set_phys_base(phys_base);
}

extern var __kernel_text_begin: u8;
extern var __kernel_text_end: u8;
extern var __kernel_data_begin: u8;
extern var __kernel_data_end: u8;
extern var __kernel_rodata_begin: u8;
extern var __kernel_rodata_end: u8;
extern var __physical_base: u8;

pub fn bootstrap_kernel_paging() !usize {
  // Setup some paging
  const new_root = try make_page_table();

  try map_kernel_section(new_root, &__kernel_text_begin, &__kernel_text_end, code());
  try map_kernel_section(new_root, &__kernel_data_begin, &__kernel_data_end, data());
  try map_kernel_section(new_root, &__kernel_rodata_begin, &__kernel_rodata_end, rodata());

  return new_root;
}

pub fn add_physical_mapping(new_root: usize, phys: usize, size: usize) !void {
  try map_phys(.{
    .virt = @ptrToInt(&__physical_base) + phys,
    .phys = phys,
    .size = size,
    .perm = data(),
    .root = new_root,
  });
}

pub fn map_phys_range(phys: usize, phys_end: usize, perm: perms, paging_root: ?u64) !void {
  var beg = phys;
  while(beg < phys_end): (beg += page_sizes[0]) {
    try unmap(.{
      .virt = @ptrToInt(&__physical_base) + beg,
      .size = page_sizes[0],
      .reclaim_pages = false,
      .root = paging_root,
    });

    try map_phys(.{
      .virt = @ptrToInt(&__physical_base) + beg,
      .phys = beg,
      .size = page_sizes[0],
      .perm = perm,
      .root = paging_root,
    });
  }
}

pub fn map_phys_struct(comptime T: type, phys: usize, perm: perms) !*T {
  const struct_size = @sizeOf(T);
  try map_phys_size(phys, struct_size, perm);
  return &pmm.access_phys(T, phys)[0];
}

pub fn map_phys_size(phys: usize, size: usize, perm: perms) !void {
  const page_addr_low = libalign.align_down(usize, page_sizes[0], phys);
  const page_addr_high = libalign.align_up(usize, page_sizes[0], phys + size);

  try map_phys_range(page_addr_low, page_addr_high, perm, null);
}

pub fn finalize_kernel_paging(new_root: u64) !void {
  try platform.prepare_paging();
  try set_paging_root(new_root, @ptrToInt(&__physical_base));
}

fn map_kernel_section(new_paging_root: u64, start: *u8, end: *u8, perm: perms) !void {
  const section_size = libalign.align_up(usize, platform.page_sizes[0], @ptrToInt(end) - @ptrToInt(start));
  try map_phys(.{
    .virt = @ptrToInt(start),
    .phys = @ptrToInt(start) - 0xffffffff80000000,
    .size = section_size,
    .perm = perm,
    .root = new_paging_root,
  });
}

fn map_loop(virt: *usize, phys: ?*usize, size: *usize, root: ?u64, perm: perms) !void {
  const start_virt = virt.*;

  if(!is_aligned(virt, phys, 0) or !libalign.is_aligned(usize, page_sizes[0], size.*)) {
    // virt, phys and size all need to be aligned to page_sizes[0].
    return error.BadAlignment;
  }

  const root_ptr = &pmm.access_phys(page_table, root orelse get_current_paging_root())[0];

  errdefer {
    // Unwind loop
    if(start_virt != virt.*) {
      unmap(.{
        .virt = start_virt,
        .size = virt.* - start_virt,
        .reclaim_pages = phys == null,
        .root = root,
      }) catch |err| {
        log("Unable to unmap partially failed mapping: {}\n", .{@errorName(err)});
        unreachable;
      };
    }
  }

  while(size.* != 0)
    try map_impl(virt, phys, size, root_ptr, perm);
}

fn is_aligned(virt: *usize, phys: ?*usize, comptime level: usize) bool {
  if(!libalign.is_aligned(usize, page_sizes[level], virt.*)) {
    return false;
  }
  if(phys == null) {
    return true;
  }
  return libalign.is_aligned(usize, page_sizes[level], phys.?.*);
}

fn map_impl(virt: *usize, phys: ?*usize, size: *usize, root: *page_table, perm: perms) !void {
  var curr = root;

  inline for(range_reverse(paging_levels)) |level| {
    if(size.* >= page_sizes[level] and is_aligned(virt, phys, level) and level < platform.allowed_mapping_levels()) {
      if(phys != null) {
        try map_at_level(level, virt.*, phys.?.*, root, perm);
      }
      else {
        try map_at_level(level, virt.*, try pmm.alloc_phys(page_sizes[level]), root, perm);
      }

      if(phys != null)
        phys.?.* += page_sizes[level];

      virt.* += page_sizes[level];
      size.* -= page_sizes[level];
      return;
    }
  }
  return error.map_impl;
}

fn map_at_level(comptime level: usize, virt: usize, phys: usize, root: *page_table, perm: perms) !void {
  const pte = try make_pte(virt, level, perm, root);
  try pte.set_mapping(level, phys, perm);
}

fn make_pte(virt: usize, level: usize, perm: perms, root: *page_table) !*page_table_entry {
  var current_table = root;
  inline for(range_reverse(paging_levels)) |current_level| {
    const pte = index_into_table(current_table, virt, current_level);
    if(level == current_level)
      return pte;

    if(!pte.is_present(current_level)) {
      const addr = try make_page_table();

      pte.set_table(current_level, addr, perm) catch |err| switch(err) {
        error.AlreadyPresent => unreachable,
      };
    }
    else {
      if(pte.is_mapping(current_level))
        return error.AlreadyPresent;

      pte.add_table_perms(current_level, perm) catch |err| switch(err) {
        error.IsNotTable => unreachable,
      };
    }

    current_table = pte.get_table(current_level) catch |err| switch(err) {
      error.IsNotTable => unreachable,
    };
  }
  return error.make_pte;
}

fn unmap_impl(virt: *usize, size: *usize, reclaim_pages: bool, root_in: ?u64) !void {
  const root: *page_table = &pmm.access_phys(page_table, root_in orelse get_current_paging_root())[0];

  while(size.* != 0)
    try unmap_at_level(virt, size, reclaim_pages, root, paging_levels - 1);
}

fn unmap_at_level(virt: *usize, size: *usize, reclaim_pages: bool, table: *page_table, comptime level: usize) !void {
  const pte = index_into_table(table, virt.*, level);

  if(pte.is_present(level)) {
    if(pte.is_mapping(level)) {
      if(page_sizes[level] <= size.*) {
        size.* -= page_sizes[level];
        virt.* += page_sizes[level];

        if(reclaim_pages)
          pmm.free_phys(pte.physaddr(level), page_sizes[level]);

        pte.clear(level);
        
        platform.invalidate_mapping(virt.*);
        return;
      }
      else {
        return error.NoPartialUnmapping;
      }
    }
    else { // Table
      if(level == 0) {
        return error.CorruptPageTables;
      }
      else {
        return unmap_at_level(virt, size, reclaim_pages, pte.get_table(level) catch unreachable, level - 1);
      }
    }
  } else {
    if(size.* <= page_sizes[level]) {
      virt.* += size.*;
      size.* = 0;
      return;
    }
    size.* -= page_sizes[level];
    virt.* += page_sizes[level];
  }
}

pub fn print_paging(root: u64) void {
  log("Dumping page tables from root 0x{x}\n", .{root});
  print_impl(&pmm.access_phys(page_table, root)[0], paging_levels - 1);
}

fn print_impl(root: *page_table, comptime level: usize) void {
  var offset: u32 = 0;
  while(offset<0x1000): (offset += 8) {
    const ent = @intToPtr(*page_table_entry, @ptrToInt(root) + offset);
    if(ent.is_present(level)) {
      var cnt = paging_levels - level - 1;
      while(cnt != 0) {
        log(" ", .{});
        cnt -= 1;
      }
      log("Index {x:0>3}: {}\n", .{offset/8, ent});
      if(level != 0)
        if(ent.is_table(level))
          print_impl(ent.get_table(level) catch unreachable, level - 1);
    }
  }
}
