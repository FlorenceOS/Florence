const os = @import("root").os;

const platform = os.platform;

const log = os.log;

const libalign      = os.lib.libalign;
const range         = os.lib.range.range;
const range_reverse = os.lib.range.range_reverse;

const pmm = os.memory.pmm;

pub var CurrentContext: os.platform.paging.PagingContext = undefined;

pub fn init() void {
  os.platform.paging.PagingContext.read_current();
}

pub fn map(args: struct {
  virt: usize,
  size: usize,
  perm: Perms,
  memtype: platform.paging.MemoryType,
  context: *platform.paging.PagingContext = &CurrentContext,
}) !void {
  var argc = args;
  return map_impl_with_rollback(.{
    .virt = &argc.virt,
    .phys = null,
    .size = &argc.size,
    .context = argc.context,
    .perm = argc.perm,
    .memtype = argc.memtype
  });
}

pub fn map_phys(args: struct {
  virt: usize,
  phys: usize,
  size: usize,
  perm: Perms,
  memtype: platform.paging.MemoryType,
  context: *platform.paging.PagingContext = &CurrentContext,
}) !void {
  var argc = args;
  return map_impl_with_rollback(.{
    .virt = &argc.virt,
    .phys = &argc.phys,
    .size = &argc.size,
    .context = argc.context,
    .perm = argc.perm,
    .memtype = argc.memtype
  });
}

pub fn unmap(args: struct {
  virt: usize,
  size: usize,
  reclaim_pages: bool,
  context: *platform.paging.PagingContext = &CurrentContext,
}) void {
  var argc = args;
  unmap_loop(&argc.virt, &argc.size, argc.reclaim_pages, argc.context);
}

pub const Perms = struct {
  writable: bool,
  executable: bool,
  userspace: bool = false,

  pub fn allows(self: @This(), other: @This()) bool {
    if(!self.writable and other.writable)
      return false;
    if(!self.executable and other.executable)
      return false;
    if(!self.userspace and other.userspace)
      return false;
    return true;
  }

  pub fn add_perms(self: @This(), other: @This()) @This() {
    return .{
      .writable   = self.writable   or other.writable,
      .executable = self.executable or other.executable,
      .userspace  = self.userspace  or other.userspace,
    };
  }
};

pub fn rx() Perms {
  return .{
    .writable = false,
    .executable = true,
  };
}

pub fn ro() Perms {
  return .{
    .writable = false,
    .executable = false,
  };
}

pub fn rw() Perms {
  return .{
    .writable = true,
    .executable = false,
  };
}

pub fn rwx() Perms {
  return .{
    .writable = true,
    .executable = true,
  };
}

pub fn user(p: Perms) Perms {
  var ret = p;
  ret.userspace = true;
  return ret;
}

pub fn get_current_paging_root() platform.paging_root {
  return platform.current_paging_root();
}

pub fn set_context(new_context: *platform.paging.PagingContext) !void {
  new_context.apply();
  CurrentContext = new_context.*;
}

extern var __kernel_text_begin: u8;
extern var __kernel_text_end: u8;
extern var __kernel_data_begin: u8;
extern var __kernel_data_end: u8;
extern var __kernel_rodata_begin: u8;
extern var __kernel_rodata_end: u8;

pub fn bootstrap_kernel_paging() !platform.paging.PagingContext {
  // Setup some paging
  var new_context = try platform.paging.PagingContext.make_default();

  try map_kernel_section(&new_context, &__kernel_text_begin, &__kernel_text_end, rx());
  try map_kernel_section(&new_context, &__kernel_data_begin, &__kernel_data_end, rw());
  try map_kernel_section(&new_context, &__kernel_rodata_begin, &__kernel_rodata_end, ro());

  return new_context;
}

fn map_kernel_section(new_paging_context: *platform.paging.PagingContext, start: *u8, end: *u8, perm: Perms) !void {
  const virt = @ptrToInt(start);
  const phys = os.vital(translate_virt(.{.virt = virt}), "Translating kaddr");  
  const region_size = @ptrToInt(end) - virt;

  os.vital(map_phys(.{
    .virt = virt,
    .phys = phys,
    .size = region_size,
    .perm = perm,
    .memtype = .MemoryWriteBack,
    .context = new_paging_context,
  }), "Mapping kernel section");
}

// Will probably be replaced by phys_slice(T[]).map()
/// Deprecated
pub fn add_physical_mapping(args: struct {
  context: *platform.paging.PagingContext,
  phys: usize,
  size: usize,
  memtype: platform.paging.MemoryType,
}) !void {
  try map_phys(.{
    .virt = args.context.phys_to_virt(args.phys),
    .phys = args.phys,
    .size = args.size,
    .perm = rw(),
    .context = args.context,
    .memtype = args.memtype,
  });
}

// Will probably be replaced by phys_slice(T[]).map()
/// Deprecated
pub fn remap_phys_range(args: struct {
  phys: usize,
  phys_end: usize,
  memtype: platform.paging.MemoryType,
  context: *platform.paging.PagingContext = &CurrentContext,
}) !void {
  var beg = args.phys;
  var virt = args.context.phys_to_virt(beg);
  const psz = args.context.page_size(0, virt);
  while(beg < args.phys_end): (beg += psz) {
    virt = args.context.phys_to_virt(beg);

    unmap(.{
      .virt = virt,
      .size = psz,
      .reclaim_pages = false,
      .context = args.context,
    });

    try map_phys(.{
      .virt = virt,
      .phys = beg,
      .size = psz,
      .perm = rw(),
      .memtype = args.memtype,
      .context = args.context,
    });
  }
}

// Will probably be replaced by phys_ptr(T).map()
/// Deprecated
pub fn remap_phys_struct(comptime T: type, args: struct{
  phys: usize,
  memtype: platform.paging.MemoryType,
  context: *platform.paging.PagingContext = &CurrentContext,
}) !*T {
  const struct_size = @sizeOf(T);
  try remap_phys_size(.{
    .phys = args.phys,
    .size = struct_size,
    .memtype = args.memtype,
    .context = args.context,
  });
  return &pmm.access_phys(T, args.phys)[0];
}

// Will probably be replaced by phys_slice(T[]).map()
/// Deprecated
pub fn remap_phys_size(args: struct {
  phys: usize,
  size: usize,
  memtype: platform.paging.MemoryType,
  context: *platform.paging.PagingContext = &CurrentContext,
}) !void {
  const psz = args.context.page_size(0, args.context.phys_to_virt(args.phys));
  const page_addr_low = libalign.align_down(usize, psz, args.phys);
  const page_addr_high = libalign.align_up(usize, psz, args.phys + args.size);

  try remap_phys_range(.{
    .phys = page_addr_low,
    .phys_end = page_addr_high,
    .context = args.context,
    .memtype = args.memtype,
  });
}

/// Tries to map the range. If the mapping fails,
/// it unmaps any memory it has touched.
fn map_impl_with_rollback(args: struct {
  virt: *usize,
  phys: ?*usize,
  size: *usize,
  perm: Perms,
  memtype: platform.paging.MemoryType,
  context: *platform.paging.PagingContext,
}) !void {
  const start_virt = args.virt.*;

  if(!is_aligned(args.virt.*, args.phys, 0, args.context) or
     !libalign.is_aligned(usize, args.context.page_size(0, args.virt.*), args.size.*)) {
    // virt, phys and size all need to be aligned
    return error.BadAlignment;
  }

  errdefer {
    // Roll it back
    if(start_virt != args.virt.*) {
      unmap(.{
        .virt = start_virt,
        .size = args.virt.* - start_virt,
        .reclaim_pages = args.phys == null,
        .context = args.context,
      });
    }
  }

  const root = args.context.root_table(args.virt.*);
  try map_impl(args.virt, args.phys, args.size, root, args.perm, args.memtype, args.context);

  if(args.size.* != 0)
    return error.IncompleteMapping;
}

fn is_aligned(virt: usize, phys: ?*usize, level: anytype, context: *platform.paging.PagingContext) bool {
  if(!libalign.is_aligned(usize, context.page_size(level, virt), virt))
    return false;

  if(phys) |p|
    return libalign.is_aligned(usize, context.page_size(level, virt), p.*);

  return true;
  
}

const MapError = error{
  AlreadyPresent,
  OutOfMemory,
  PhysAllocTooSmall,
};

fn map_impl(
  virt: *usize,
  phys: ?*usize,
  size: *usize,
  table: anytype,
  perm: Perms,
  memtype: platform.paging.MemoryType,
  context: *platform.paging.PagingContext,
) MapError!void {
  var curr = table;

  const children = table.skip_to(virt.*);

  for(children) |*child| {
    switch(table.decode_child(child)) {
      .Mapping => return error.AlreadyPresent,
      .Table => |*tbl| {
        try map_impl(virt, phys, size, tbl.*, perm, memtype, context);
        if(!tbl.perms.allows(perm)) {
          tbl.add_perms(perm);
          context.invalidate(virt.*);
        }
      },
      .Empty => {
        const dom = table.child_domain(virt.*);

        // Should we map at the current level?
        if(dom.ptr == virt.* and dom.len <= size.*
            and context.can_map_at_level(table.level() - 1)
            and is_aligned(virt.*, phys, table.level() - 1, context)) {
          const m = try table.make_child_mapping(child, if(phys) |p| p.* else null, perm, memtype);
          const step = dom.len;
          if(step >= size.*) {
            size.* = 0;
            return;
          }
          else {
            size.* -= step;
            virt.* += step;
            if(phys) |p|
              p.* += step;
          }
        } else {
          const tbl = try table.make_child_table(child, perm);
          try map_impl(virt, phys, size, tbl, perm, memtype, context);
        }
      },
    }
    if(size.* == 0)
      return;
  }
}

fn translate_virt_impl(
  virt: usize,
  table: anytype,
  context: *platform.paging.PagingContext,
) error{NotPresent}!usize {
  const child = table.decode_child(&table.skip_to(virt)[0]);
  const dom = table.child_domain(virt);

  switch(child) {
    .Empty => return error.NotPresent,
    .Mapping => |m| return m.mapped_bytes().ptr + virt - dom.ptr,
    .Table => |t| return translate_virt_impl(virt, t, context),
  }
}

pub fn translate_virt(args: struct {
  virt: usize,
  context: *platform.paging.PagingContext = &CurrentContext,
}) !usize {
  const root = args.context.root_table(args.virt);
  return translate_virt_impl(args.virt, root, args.context);
}

fn unmap_loop(
  virt: *usize,
  size: *usize,
  reclaim_pages: bool,
  context: *platform.paging.PagingContext,
) void {
  const root = context.root_table(virt.*);
  while(size.* != 0)
    unmap_iter(virt, size, reclaim_pages, root, context);
}

fn unmap_iter(
  virt: *usize,
  size: *usize,
  reclaim_pages: bool,
  table: anytype,
  context: *platform.paging.PagingContext,
) void {
  for(table.skip_to(virt.*)) |*child| {
    const dom = table.child_domain(virt.*);

    switch(table.decode_child(child)) {
      .Empty => {
        if(dom.len >= size.*){
          size.* = 0;
          return;
        }
        virt.* += dom.len;
        size.* -= dom.len;
      },
      .Table => |tbl| unmap_iter(virt, size, reclaim_pages, tbl, context),
      .Mapping => |mapping| {
        if(dom.len > size.* or dom.ptr != virt.*)
          @panic("No partial unmapping support yet =(");

        if(reclaim_pages)
          pmm.free_phys(mapping.phys, dom.len);

        child.* = context.encode_empty(mapping.level);
        context.invalidate(virt.*);

        virt.* += dom.len;
        size.* -= dom.len;
      },
    }
    if(size.* == 0)
      return;
  }
}

pub fn print_paging(root: *platform.PagingRoot) void {
  log("Paging: {x}\n", .{root});
  for(platform.root_tables(root)) |table| {
    log("Dumping page tables from root {x}\n", .{table});
    print_impl(table, paging_levels - 1);
  }
}

fn print_impl(root: *page_table, comptime level: usize) void {
  var offset: u32 = 0;
  var had_any: bool = false;
  while(offset < platform.paging.page_sizes[0]): (offset += 8) {
    const ent = @intToPtr(*page_table_entry, @ptrToInt(root) + offset);
    if(ent.is_present(level)) {
      had_any = true;
      var cnt = paging_levels - level - 1;
      while(cnt != 0) {
        log(" ", .{});
        cnt -= 1;
      }
      log("Index {x:0>3}: {}\n", .{offset/8, ent});
      if(level != 0) {
        if(ent.is_table(level))
          print_impl(ent.get_table(level) catch unreachable, level - 1);
      }
    }
  }
  if(!had_any) {
    var cnt = paging_levels - level - 1;
    while(cnt != 0) {
      log(" ", .{});
      cnt -= 1;
    }
    log("Empty table\n", .{});
  }
}
