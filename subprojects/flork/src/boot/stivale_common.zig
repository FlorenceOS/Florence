usingnamespace @import("root").preamble;

const paging = os.memory.paging;
const platform = os.platform;
const libalign = lib.util.libalign;

pub const MemmapEntry = packed struct {
    base: u64,
    length: u64,
    type: u32,
    unused: u32,

    pub fn format(self: *const MemmapEntry, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Base: 0x{X}, length: 0x{X}, type=0x{X}", .{ self.base, self.length, self.type });
    }
};

pub fn consume_physmem(ent: *const MemmapEntry) void {
    if (ent.type != 1)
        return;

    os.log("Stivale: Consuming 0x{X} to 0x{X}\n", .{ ent.base, ent.base + ent.length });
    os.memory.pmm.consume(ent.base, ent.length);
}

pub fn map_phys(ent: *const MemmapEntry, context: *platform.paging.PagingContext) void {
    if (ent.type != 1 and ent.type != 0x1000)
        return;

    var new_ent = ent.*;

    new_ent.base = libalign.alignDown(u64, platform.paging.page_sizes[0], new_ent.base);
    // If there is nothing left of the entry
    if (new_ent.base >= ent.base + ent.length)
        return;

    new_ent.length = libalign.alignUp(u64, platform.paging.page_sizes[0], new_ent.length);
    if (new_ent.length == 0)
        return;

    os.log("Stivale: Mapping phys mem 0x{X} to 0x{X}\n", .{ new_ent.base, new_ent.base + new_ent.length });

    os.vital(paging.add_physical_mapping(.{
        .context = context,
        .phys = new_ent.base,
        .size = new_ent.length,
    }), "mapping physical stivale mem");
}

pub fn phys_high(map: []const MemmapEntry) usize {
    if (map.len == 0)
        @panic("No memmap!");
    const ent = map[map.len - 1];
    return ent.base + ent.length;
}

pub fn init_paging() void {
    os.platform.paging.init();

    const base: usize = switch (os.platform.arch) {
        .aarch64 => 0xFFFF800000000000,
        .x86_64 => if (os.platform.paging.is_5levelpaging())
            @as(usize, 0xFF00000000000000)
        else
            0xFFFF800000000000,
        else => @panic("Phys base for platform unknown!"),
    };

    const context = &os.memory.paging.kernel_context;

    context.wb_virt_base = base;
    context.wc_virt_base = base;
    context.uc_virt_base = base;
    context.max_phys = 0x7F0000000000;
}
