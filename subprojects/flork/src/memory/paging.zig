usingnamespace @import("root").preamble;

const platform = os.platform;
const log = os.log;
const libalign = lib.util.libalign;
const range = lib.util.range.range;
const rangeReverse = lib.util.range.rangeReverse;
const pmm = os.memory.pmm;

const Context = *platform.paging.PagingContext;

const MapError = error{
    AlreadyPresent,
    OutOfMemory,
    PhysAllocTooSmall,
};

pub const Perms = struct {
    writable: bool,
    executable: bool,
    userspace: bool = false,

    pub fn allows(self: @This(), other: @This()) bool {
        if (!self.writable and other.writable)
            return false;
        if (!self.executable and other.executable)
            return false;
        if (!self.userspace and other.userspace)
            return false;
        return true;
    }

    pub fn addPerms(self: @This(), other: @This()) @This() {
        return .{
            .writable = self.writable or other.writable,
            .executable = self.executable or other.executable,
            .userspace = self.userspace or other.userspace,
        };
    }
};


extern var __kernel_text_begin: u8;
extern var __kernel_text_end: u8;
extern var __kernel_data_begin: u8;
extern var __kernel_data_end: u8;
extern var __kernel_rodata_begin: u8;
extern var __kernel_rodata_end: u8;
extern var __bootstrap_stack_bottom: u8;
extern var __bootstrap_stack_top: u8;

pub var kernel_context: os.platform.paging.PagingContext = undefined;

fn mapKernelSection(new_paging_context: Context, start: *u8, end: *u8, perm: Perms) !void {
    const virt = @ptrToInt(start);
    const phys = os.vital(translateVirt(.{ .virt = virt }), "Translating kaddr");
    const region_size = @ptrToInt(end) - virt;

    os.vital(mapPhys(.{
        .virt = virt,
        .phys = phys,
        .size = region_size,
        .perm = perm,
        .memtype = .MemoryWriteBack,
        .context = new_paging_context,
    }), "Mapping kernel section");
}

/// Tries to map the range. If the mapping fails,
/// it unmaps any memory it has touched.
fn mapImplWithRollback(args: struct {
    virt: *usize,
    phys: ?*usize,
    size: *usize,
    perm: Perms,
    memtype: platform.paging.MemoryType,
    context: Context,
}) !void {
    const start_virt = args.virt.*;

    if (!is_aligned(args.virt.*, args.phys, 0, args.context) or
        !libalign.isAligned(usize, os.platform.paging.page_sizes[0], args.size.*))
    {
        // virt, phys and size all need to be aligned
        return error.BadAlignment;
    }

    errdefer {
        // Roll it back
        if (start_virt != args.virt.*) {
            unmap(.{
                .virt = start_virt,
                .size = args.virt.* - start_virt,
                .reclaim_pages = args.phys == null,
                .context = args.context,
            });
        }
    }

    const root = args.context.root_table(args.virt.*);
    try mapImpl(args.virt, args.phys, args.size, root, args.perm, args.memtype, args.context);

    if (args.size.* != 0)
        return error.IncompleteMapping;
}

fn is_aligned(virt: usize, phys: ?*usize, level: anytype, context: Context) bool {
    if (!libalign.isAligned(usize, os.platform.paging.page_sizes[level], virt))
        return false;

    if (phys) |p|
        return libalign.isAligned(usize, os.platform.paging.page_sizes[level], p.*);

    return true;
}

fn mapImpl(
    virt: *usize,
    phys: ?*usize,
    size: *usize,
    table: anytype,
    perm: Perms,
    memtype: platform.paging.MemoryType,
    context: Context,
) MapError!void {
    var curr = table;

    const children = table.skip_to(virt.*);

    for (children) |*child| {
        switch (table.decode_child(child)) {
            .Mapping => return error.AlreadyPresent,
            .Table => |*tbl| {
                try mapImpl(virt, phys, size, tbl.*, perm, memtype, context);
                if (!tbl.perms.allows(perm)) {
                    tbl.addPerms(perm);
                    context.invalidate(virt.*);
                }
            },
            .Empty => {
                const dom = table.child_domain(virt.*);

                // Should we map at the current level?
                if (dom.ptr == virt.* and dom.len <= size.* and context.can_map_at_level(table.level() - 1) and is_aligned(virt.*, phys, table.level() - 1, context)) {
                    const m = try table.make_child_mapping(child, if (phys) |p| p.* else null, perm, memtype);
                    const step = dom.len;
                    if (step >= size.*) {
                        size.* = 0;
                        return;
                    } else {
                        size.* -= step;
                        virt.* += step;
                        if (phys) |p|
                            p.* += step;
                    }
                } else {
                    const tbl = try table.make_child_table(child, perm);
                    try mapImpl(virt, phys, size, tbl, perm, memtype, context);
                }
            },
        }
        if (size.* == 0)
            return;
    }
}

fn translateVirtImpl(
    virt: usize,
    table: anytype,
    context: Context,
) error{NotPresent}!usize {
    const child = table.decode_child(&table.skip_to(virt)[0]);
    const dom = table.child_domain(virt);

    switch (child) {
        .Empty => return error.NotPresent,
        .Mapping => |m| return m.mapped_bytes().ptr + virt - dom.ptr,
        .Table => |t| return translateVirtImpl(virt, t, context),
    }
}

fn unmapLoop(
    virt: *usize,
    size: *usize,
    reclaim_pages: bool,
    context: Context,
) void {
    const root = context.root_table(virt.*);
    while (size.* != 0)
        unmapIter(virt, size, reclaim_pages, root, context);
}

fn unmapIter(
    virt: *usize,
    size: *usize,
    reclaim_pages: bool,
    table: anytype,
    context: Context,
) void {
    for (table.skip_to(virt.*)) |*child| {
        const dom = table.child_domain(virt.*);

        switch (table.decode_child(child)) {
            .Empty => {
                if (dom.len >= size.*) {
                    size.* = 0;
                    return;
                }
                virt.* += dom.len;
                size.* -= dom.len;
            },
            .Table => |tbl| unmapIter(virt, size, reclaim_pages, tbl, context),
            .Mapping => |mapping| {
                if (dom.len > size.* or dom.ptr != virt.*)
                    @panic("No partial unmapping");

                if (reclaim_pages)
                    pmm.free_phys(mapping.phys, dom.len);

                child.* = context.encode_empty(mapping.level);
                context.invalidate(virt.*);

                virt.* += dom.len;
                size.* -= dom.len;
            },
        }
        if (size.* == 0)
            return;
    }
}

fn printImpl(root: *page_table, comptime level: usize) void {
    var offset: u32 = 0;
    var had_any: bool = false;
    while (offset < platform.paging.page_sizes[0]) : (offset += 8) {
        const ent = @intToPtr(*page_table_entry, @ptrToInt(root) + offset);
        if (ent.is_present(level)) {
            had_any = true;
            var cnt = paging_levels - level - 1;
            while (cnt != 0) {
                log(" ", .{});
                cnt -= 1;
            }
            log("Index {x:0>3}: {}\n", .{ offset / 8, ent });
            if (level != 0) {
                if (ent.is_table(level))
                    printImpl(ent.get_table(level) catch unreachable, level - 1);
            }
        }
    }
    if (!had_any) {
        var cnt = paging_levels - level - 1;
        while (cnt != 0) {
            log(" ", .{});
            cnt -= 1;
        }
        log("Empty table\n", .{});
    }
}

pub fn init() void {
    os.platform.paging.PagingContext.read_current();
}

pub fn map(args: struct {
    virt: usize,
    size: usize,
    perm: Perms,
    memtype: platform.paging.MemoryType,
    context: Context = &kernel_context,
}) !void {
    var argc = args;
    return mapImplWithRollback(.{
        .virt = &argc.virt,
        .phys = null,
        .size = &argc.size,
        .context = argc.context,
        .perm = argc.perm,
        .memtype = argc.memtype,
    });
}

pub fn mapPhys(args: struct {
    virt: usize,
    phys: usize,
    size: usize,
    perm: Perms,
    memtype: platform.paging.MemoryType,
    context: Context = &kernel_context,
}) !void {
    var argc = args;
    return mapImplWithRollback(.{
        .virt = &argc.virt,
        .phys = &argc.phys,
        .size = &argc.size,
        .context = argc.context,
        .perm = argc.perm,
        .memtype = argc.memtype,
    });
}

pub fn unmap(args: struct {
    virt: usize,
    size: usize,
    reclaim_pages: bool,
    context: Context = &kernel_context,
}) void {
    var argc = args;
    unmapLoop(&argc.virt, &argc.size, argc.reclaim_pages, argc.context);
}

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

pub fn getCurrentPagingRoot() platform.paging_root {
    return platform.current_paging_root();
}

pub fn setContext(new_context: Context) !void {
    new_context.apply();
    kernel_context = new_context.*;
}

pub fn bootstrapKernelPaging() !platform.paging.PagingContext {
    // Setup some paging
    var new_context = try platform.paging.PagingContext.make_default();

    try mapKernelSection(&new_context, &__kernel_text_begin, &__kernel_text_end, rx());
    try mapKernelSection(&new_context, &__kernel_data_begin, &__kernel_data_end, rw());
    try mapKernelSection(&new_context, &__kernel_rodata_begin, &__kernel_rodata_end, ro());
    try mapKernelSection(&new_context, &__bootstrap_stack_bottom, &__bootstrap_stack_top, rw());

    return new_context;
}

pub fn mapPhysmem(args: struct {
    context: Context,
    map_limit: usize,
}) !void {
    // Map once with each memory type
    try mapPhys(.{
        .virt = args.context.phys_to_write_back_virt(0),
        .phys = 0,
        .size = args.map_limit,
        .perm = rw(),
        .context = args.context,
        .memtype = .MemoryWriteBack,
    });

    try mapPhys(.{
        .virt = args.context.phys_to_write_combining_virt(0),
        .phys = 0,
        .size = args.map_limit,
        .perm = rw(),
        .context = args.context,
        .memtype = .DeviceWriteCombining,
    });

    try mapPhys(.{
        .virt = args.context.phys_to_uncached_virt(0),
        .phys = 0,
        .size = args.map_limit,
        .perm = rw(),
        .context = args.context,
        .memtype = .DeviceUncacheable,
    });
}

pub fn translateVirt(args: struct {
    virt: usize,
    context: Context = &kernel_context,
}) !usize {
    const root = args.context.root_table(args.virt);
    return translateVirtImpl(args.virt, root, args.context);
}

pub fn printPaging(root: *platform.PagingRoot) void {
    log("Paging: {x}\n", .{root});
    for (platform.root_tables(root)) |table| {
        log("Dumping page tables from root {x}\n", .{table});
        printImpl(table, paging_levels - 1);
    }
}

pub fn switchToContext(context: Context) void {
    const state = os.platform.get_and_disable_interrupts();
    context.apply();
    os.platform.get_current_task().paging_context = context;
    os.platform.set_interrupts(state);
}
