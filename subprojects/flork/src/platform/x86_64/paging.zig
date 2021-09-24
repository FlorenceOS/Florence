usingnamespace @import("root").preamble;

const log = lib.output.log.scoped(.{
    .prefix = "x86_64 Paging",
    .filter = .info,
}).write;

const regs = @import("regs.zig");
const paging = @import("../paging.zig");

pub const page_sizes = [_]usize{
    0x1000, // 4K
    0x200000, // 2M
    0x40000000, // 1G
    0x8000000000, // 512G
    0x1000000000000, // 256T
};

const LevelType = u3;
const PatIndex = u3;

const la64: u64 = 1 << 12;
const cr3 = regs.ControlRegister(u64, "cr3");
const cr4 = regs.ControlRegister(u64, "cr4");

fn PATContext() type {
    const PATEncoding = u8;
    const PATValue = u64;

    const ia32_pat = regs.MSR(PATValue, 0x00000277);

    const uncacheable_encoding = 0x00;
    const write_combining_encoding = 0x01;
    const writethrough_encoding = 0x04;
    const write_back_encoding = 0x06;

    return struct {
        // The value of IA32_PAT itself
        value: PATValue,

        // Cache the indices for each memory type
        uncacheable: ?PatIndex,
        write_combining: ?PatIndex,
        writethrough: ?PatIndex,
        write_back: ?PatIndex,

        pub fn init_from_pat_value(value: PATValue) @This() {
            return .{
                .value = value,
                .uncacheable = find_pat_index(value, uncacheable_encoding),
                .write_combining = find_pat_index(value, write_combining_encoding),
                .writethrough = find_pat_index(value, writethrough_encoding),
                .write_back = find_pat_index(value, write_back_encoding),
            };
        }

        fn encoding_at_index(value: PATValue, idx: PatIndex) PATEncoding {
            return @truncate(u8, value >> (@as(u6, idx) * 8));
        }

        fn memory_type_at_index(self: *const @This(), idx: PatIndex) ?MemoryType {
            return switch (encoding_at_index(self.value, idx)) {
                uncacheable_encoding => .DeviceUncacheable,
                write_combining_encoding => .DeviceWriteCombining,
                writethrough_encoding => .MemoryWritethrough,
                write_back_encoding => .MemoryWriteBack,
                else => null,
            };
        }

        fn find_pat_index(pat: PATValue, enc: PATEncoding) ?PatIndex {
            var idx: PatIndex = 0;
            while (true) : (idx += 1) {
                if (encoding_at_index(pat, idx) == enc)
                    return idx;

                if (idx == 7)
                    return null;
            }
        }

        pub fn find_memtype(self: *const @This(), memtype: MemoryType) ?PatIndex {
            var idx: PatIndex = 0;
            while (true) : (idx += 1) {
                if (self.memory_type_at_index(idx) == memtype)
                    return idx;

                if (idx == 7)
                    return null;
            }
        }

        pub fn apply(self: *const @This()) void {
            ia32_pat.write(self.value);
        }

        pub fn get_active() ?@This() {
            const id = regs.cpuid(0x00000001);
            if (id) |i| {
                if (((i.edx >> 16) & 1) != 0)
                    return init_from_pat_value(ia32_pat.read());
            }
            return null;
        }

        pub fn make_default() ?@This() {
            const default = comptime init_from_pat_value(0
            // We set writeback as index 0 for our page tables
            | write_back_encoding << 0
            // The order of the rest shouldn't matter
            | write_combining_encoding << 8 | writethrough_encoding << 16 | uncacheable_encoding << 24);
            return default;
        }
    };
}

fn level_size(level: LevelType) u64 {
    return @as(u64, 0x1000) << (@as(u6, level) * 9);
}

pub fn make_page_table() !u64 {
    const pt = try os.memory.pmm.allocPhys(0x1000);
    const pt_bytes = os.platform.phys_slice(u8).init(pt, 0x1000);
    @memset(pt_bytes.to_slice_writeback().ptr, 0x00, 0x1000);
    return pt;
}

pub fn is_5levelpaging() bool {
    return cr4.read() & la64 != 0;
}

var gigapage_allowed: bool = false;

pub fn init() void {
    gigapage_allowed = if (regs.cpuid(0x80000001)) |i| ((i.edx >> 26) & 1) == 1 else false;
}

pub const PagingContext = struct {
    pat: ?PATContext(),
    cr3_val: u64,
    level5paging: bool,

    wb_virt_base: u64 = undefined,
    wc_virt_base: u64 = undefined,
    uc_virt_base: u64 = undefined,
    max_phys: u64 = undefined,

    pub fn apply(self: *@This()) void {
        // First apply the PAT, shouldn't cause any errors
        if (self.pat) |pat|
            @call(.{ .modifier = .always_inline }, PATContext().apply, .{&pat});

        regs.IA32_EFER.write(regs.IA32_EFER.read() | (1 << 11)); // NXE

        // Set 5 level paging bit
        const old_cr4 = cr4.read();
        cr4.write(if (self.level5paging)
            old_cr4 | la64
        else
            old_cr4 & ~la64);

        @call(.{ .modifier = .always_inline }, cr3.write, .{self.cr3_val});
    }

    pub fn read_current() void {
        const curr = &os.memory.paging.kernel_context;

        curr.pat = PATContext().get_active();
        curr.cr3_val = cr3.read();

        // Test if 5 level paging currently is enabled
        curr.level5paging = is_5levelpaging();
    }

    pub fn make_default() !@This() {
        const curr = &os.memory.paging.kernel_context;

        const pt = try make_page_table();

        {
            // Initialize top half with tables
            const root = TablePTE{
                .phys = pt,
                .curr_level = if (curr.level5paging) 5 else 4,
                .context = curr,
                .perms = os.memory.paging.rwx(),
                .underlying = null,
            };

            for (root.get_children()[256..]) |*child| {
                _ = try root.make_child_table(child, .{
                    .userspace = false,
                    .writable = true,
                    .executable = true,
                });
            }
        }

        // 32TB ought to be enough for anyone...
        const max_phys = 0x200000000000;

        const curr_base = os.memory.paging.kernel_context.wb_virt_base;

        return @This(){
            .pat = PATContext().make_default(),
            .cr3_val = pt,
            .level5paging = curr.level5paging,
            .wb_virt_base = curr_base,
            .wc_virt_base = curr_base + max_phys,
            .uc_virt_base = curr_base + max_phys * 2,
            .max_phys = max_phys,
        };
    }

    pub fn make_userspace() !@This() {
        const curr_kernel = &os.memory.paging.kernel_context;
        var result = curr_kernel.*;

        const pt = try make_page_table();
        result.cr3_val = pt;
        errdefer result.deinit();

        {
            // Initialize top half with tables
            const root = TablePTE{
                .phys = pt,
                .curr_level = if (curr_kernel.level5paging) 5 else 4,
                .context = &result,
                .perms = os.memory.paging.rwx(),
                .underlying = null,
            };

            const kernel_root = curr_kernel.root_table(0).get_children();

            // Copy higher half into the page table
            std.mem.copy(u64, root.get_children()[256..], kernel_root[256..]);
        }

        return result;
    }

    pub fn deinit(self: *@This()) void {
        log(.notice, "TODO: PagingContext deinit\n", .{});
    }

    pub fn can_map_at_level(self: *const @This(), level: LevelType) bool {
        return level < @as(LevelType, 2) + @boolToInt(gigapage_allowed);
    }

    pub fn check_phys(self: *const @This(), phys: u64) void {
        if (comptime (std.debug.runtime_safety)) {
            if (phys > self.max_phys) {
                log(null, "Physaddr: 0x{X}", .{phys});
                @panic("Physical address out of range");
            }
        }
    }

    pub fn physToWriteBackVirt(self: *const @This(), phys: u64) u64 {
        self.check_phys(phys);
        return self.wb_virt_base + phys;
    }

    pub fn physToWriteCombiningVirt(self: *const @This(), phys: u64) u64 {
        self.check_phys(phys);
        return self.wc_virt_base + phys;
    }

    pub fn physToUncachedVirt(self: *const @This(), phys: u64) u64 {
        self.check_phys(phys);
        return self.uc_virt_base + phys;
    }

    pub fn make_heap_base(self: *const @This()) u64 {
        // Just after last physical memory mapping
        return self.uc_virt_base + self.max_phys;
    }

    pub fn root_table(self: *@This(), virt: u64) TablePTE {
        return .{
            .phys = self.cr3_val,
            .curr_level = if (self.level5paging) 5 else 4,
            .context = self,
            .perms = os.memory.paging.rwx(),
            .underlying = null,
        };
    }

    pub fn decode(self: *@This(), enc: *EncodedPTE, level: LevelType) PTE {
        var pte = PTEEncoding{ .raw = enc.* };

        if (!pte.present.read())
            return .Empty;
        if (!pte.is_mapping.read() and level != 0)
            return .{ .Table = self.decode_table(enc, level) };
        return .{ .Mapping = self.decode_mapping(enc, level) };
    }

    fn decode_memtype(self: *@This(), map: MappingEncoding, level: LevelType) ?MemoryType {
        // TODO: MTRR awareness (?)
        // right now we assume all MTRRs are WB
        if (self.pat) |pat| {
            // Formula for PAT index is 4*PAT + 2*CD + 1*WT
            var pat_idx: PatIndex = 0;
            const pat_bit = if (level == 0) map.is_mapping_or_pat_low.read() else map.pat_high.read();
            if (pat_bit)
                pat_idx += 4;
            if (map.cache_disable.read())
                pat_idx += 2;
            if (map.writethrough.read())
                pat_idx += 1;

            return pat.memory_type_at_index(pat_idx);
        } else {
            switch (map.cache_disable.read()) {
                true => return MemoryType.DeviceUncacheable,
                false => switch (map.writethrough.read()) {
                    true => return MemoryType.MemoryWritethrough,
                    false => return MemoryType.MemoryWriteBack,
                },
            }
        }
    }

    pub fn decode_mapping(self: *@This(), enc: *EncodedPTE, level: LevelType) MappingPTE {
        const map = MappingEncoding{ .raw = enc.* };

        const memtype: MemoryType = self.decode_memtype(map, level) orelse @panic("Unknown memory type");

        return .{
            .context = self,
            .phys = if (level == 0) enc.* & phys_bitmask else enc.* & phys_bitmask_high,
            .level = level,
            .memtype = memtype,
            .underlying = @ptrCast(*MappingEncoding, enc),
            .perms = .{
                .writable = map.writable.read(),
                .executable = !map.execute_disable.read(),
                .userspace = map.user.read(),
            },
        };
    }

    pub fn decode_table(self: *@This(), enc: *EncodedPTE, level: LevelType) TablePTE {
        const tbl = TableEncoding{ .raw = enc.* };

        return .{
            .context = self,
            .phys = enc.* & phys_bitmask,
            .curr_level = level,
            .underlying = @ptrCast(*TableEncoding, enc),
            .perms = .{
                .writable = tbl.writable.read(),
                .executable = !tbl.execute_disable.read(),
                .userspace = tbl.user.read(),
            },
        };
    }

    pub fn encode_empty(self: *const @This(), level: LevelType) EncodedPTE {
        return 0;
    }

    pub fn encode_table(self: *const @This(), pte: TablePTE) !EncodedPTE {
        var tbl = TableEncoding{ .raw = pte.phys };

        tbl.writable.write(pte.perms.writable);
        tbl.user.write(pte.perms.userspace);
        tbl.execute_disable.write(!pte.perms.executable);

        tbl.present.write(true);
        tbl.is_mapping.write(false);

        return tbl.raw;
    }

    fn encode_memory_type(self: *const @This(), enc: *MappingEncoding, pte: MappingPTE) void {
        // TODO: MTRR awareness (?)
        // right now we assume all MTRRs are WB
        const mt = pte.memtype orelse @panic("Unknown memory type");

        if (self.pat) |pat| {
            // Formula for PAT index is 4*PAT + 2*CD + 1*WT
            const idx = pat.find_memtype(mt) orelse @panic("Could not find PAT index");

            if (idx & 4 != 0) {
                if (pte.level == 0) {
                    enc.is_mapping_or_pat_low.write(true);
                } else {
                    enc.pat_high.write(true);
                }
            }
            if (idx & 2 != 0)
                enc.cache_disable.write(true);
            if (idx & 1 != 0)
                enc.writethrough.write(true);
        } else {
            switch (mt) {
                .MemoryWritethrough => enc.writethrough.write(true),
                .DeviceUncacheable => enc.cache_disable.write(true),
                .MemoryWriteBack => {},
                else => @panic("Cannot set memory type"),
            }
        }
    }

    pub fn encode_mapping(self: *const @This(), pte: MappingPTE) !EncodedPTE {
        var map = MappingEncoding{ .raw = pte.phys };

        // writethrough: bf.Boolean(u64, 3),
        // cache_disable: bf.Boolean(u64, 4),
        // is_mapping_or_pat_low: bf.Boolean(u64, 7),
        // pat_high: bf.Boolean(u64, 12),

        map.present.write(true);

        if (pte.level != 0)
            map.is_mapping_or_pat_low.write(true);

        map.writable.write(pte.perms.writable);
        map.user.write(pte.perms.userspace);
        map.execute_disable.write(!pte.perms.executable);

        self.encode_memory_type(&map, pte);

        return map.raw;
    }

    pub fn domain(self: *const @This(), level: LevelType, virtaddr: u64) os.platform.virt_slice {
        return .{
            .ptr = virtaddr & ~(page_sizes[level] - 1),
            .len = page_sizes[level],
        };
    }

    pub fn invalidate(self: *const @This(), virt: u64) void {
        asm volatile (
            \\invlpg (%[virt])
            :
            : [virt] "r" (virt)
            : "memory"
        );
    }

    pub fn invalidateOtherCPUs(self: *const @This(), base: usize, size: usize) void {
        const current_cpu = os.platform.thread.get_current_cpu();

        for (os.platform.smp.cpus) |*cpu| {
            if (cpu != current_cpu)
                cpu.platform_data.invlpgIpi();
        }
    }
};

pub const MemoryType = extern enum {
    // x86 doesn't differentiate between device and normal memory (?)
    DeviceUncacheable = 0,
    MemoryUncacheable = 0,
    DeviceWriteCombining = 1,
    MemoryWritethrough = 2,
    MemoryWriteBack = 3,
};

const phys_bitmask = 0x7ffffffffffff000;
const phys_bitmask_high = 0x7fffffffffffe000;
const bf = lib.util.bitfields;

const PTEEncoding = extern union {
    raw: u64,

    present: bf.Boolean(u64, 0),
    is_mapping: bf.Boolean(u64, 7),
};

const MappingEncoding = extern union {
    raw: u64,

    present: bf.Boolean(u64, 0),
    writable: bf.Boolean(u64, 1),
    user: bf.Boolean(u64, 2),
    writethrough: bf.Boolean(u64, 3),
    cache_disable: bf.Boolean(u64, 4),
    accessed: bf.Boolean(u64, 5),
    is_mapping_or_pat_low: bf.Boolean(u64, 7),
    pat_high: bf.Boolean(u64, 12),
    execute_disable: bf.Boolean(u64, 63),
};

const TableEncoding = extern union {
    raw: u64,

    present: bf.Boolean(u64, 0),
    writable: bf.Boolean(u64, 1),
    user: bf.Boolean(u64, 2),
    accessed: bf.Boolean(u64, 5),
    is_mapping: bf.Boolean(u64, 7),
    execute_disable: bf.Boolean(u64, 63),
};

fn virt_index_at_level(vaddr: u64, level: u6) u9 {
    const shamt = 12 + level * 9;
    return @truncate(u9, (vaddr >> shamt));
}

const MappingPTE = struct {
    phys: u64,
    level: u3,
    memtype: ?MemoryType,
    context: *PagingContext,
    perms: os.memory.paging.Perms,
    underlying: *MappingEncoding,

    pub fn mapped_bytes(self: *const @This()) os.platform.PhysBytes {
        return .{
            .ptr = self.phys,
            .len = page_sizes[self.level],
        };
    }

    pub fn get_type(self: *const @This()) ?MemoryType {
        return self.memtype;
    }
};

const EncodedPTE = u64;

const TablePTE = struct {
    phys: u64,
    curr_level: LevelType,
    context: *PagingContext,
    perms: os.memory.paging.Perms,
    underlying: ?*TableEncoding,

    pub fn get_children(self: *const @This()) []EncodedPTE {
        return os.platform.phys_slice(EncodedPTE).init(self.phys, 512).to_slice_writeback();
    }

    pub fn skip_to(self: *const @This(), virt: u64) []EncodedPTE {
        return self.get_children()[virt_index_at_level(virt, self.curr_level - 1)..];
    }

    pub fn child_domain(self: *const @This(), virt: u64) os.platform.virt_slice {
        return self.context.domain(self.curr_level - 1, virt);
    }

    pub fn decode_child(self: *const @This(), pte: *EncodedPTE) PTE {
        return self.context.decode(pte, self.curr_level - 1);
    }

    pub fn level(self: *const @This()) LevelType {
        return self.curr_level;
    }

    pub fn addPerms(self: *const @This(), perms: os.memory.paging.Perms) void {
        if (perms.executable)
            self.underlying.?.execute_disable.write(false);
        if (perms.writable)
            self.underlying.?.writable.write(true);
        if (perms.userspace)
            self.underlying.?.user.write(true);
    }

    pub fn make_child_table(self: *const @This(), enc: *u64, perms: os.memory.paging.Perms) !TablePTE {
        const pmem = try make_page_table();
        errdefer os.memory.pmm.freePhys(pmem, 0x1000);

        var result: TablePTE = .{
            .phys = pmem,
            .context = self.context,
            .curr_level = self.curr_level - 1,
            .perms = perms,
            .underlying = @ptrCast(*TableEncoding, enc),
        };

        enc.* = try self.context.encode_table(result);

        return result;
    }

    pub fn make_child_mapping(
        self: *const @This(),
        enc: *u64,
        phys: ?u64,
        perms: os.memory.paging.Perms,
        memtype: MemoryType,
    ) !MappingPTE {
        const page_size = page_sizes[self.level() - 1];
        const pmem = phys orelse try os.memory.pmm.allocPhys(page_size);
        errdefer if (phys == null) os.memory.pmm.freePhys(pmem, page_size);

        var result: MappingPTE = .{
            .level = self.level() - 1,
            .memtype = memtype,
            .context = self.context,
            .perms = perms,
            .underlying = @ptrCast(*MappingEncoding, enc),
            .phys = pmem,
        };

        enc.* = try self.context.encode_mapping(result);

        return result;
    }
};

const EmptyPte = struct {};

pub const PTE = union(paging.PTEType) {
    Mapping: MappingPTE,
    Table: TablePTE,
    Empty: EmptyPte,
};
