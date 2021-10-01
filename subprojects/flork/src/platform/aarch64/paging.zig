usingnamespace @import("root").preamble;

const log = lib.output.log.scoped(.{
    .prefix = "aarch64/paging",
    .filter = .info,
}).write;

const paging_common = @import("../paging.zig");

pub var page_sizes: []const usize = undefined;

const pages_4K = [_]usize{
    0x1000, // 4K << 0
    0x200000, // 4K << 9
    0x40000000, // 4K << 18
    0x8000000000, // 4K << 27
    0x1000000000000, // 4K << 36
};

const pages_16K = [_]usize{
    0x4000, // 16K << 0
    0x2000000, // 16K << 11
    0x1000000000, // 16K << 22
    0x800000000000, // 16K << 33
    0x400000000000000, // 16K << 44
};

const pages_64K = [_]usize{
    0x10000, // 64K << 0
    0x20000000, // 64K << 13
    0x40000000000, // 64K << 26
    0x80000000000000, // 64K << 39
};

const mair_index = u3;

fn MAIRContext() type {
    const mair_encoding = u8;
    const mair_value = u64;

    const MAIR = os.platform.msr(mair_value, "MAIR_EL1");

    // Current limitation: Outer = Inner and only non-transient

    // Device nGnRnE
    const device_uncacheable_encoding = 0b0000_00_00;

    // Device GRE
    const device_write_combining_encoding = 0b0000_11_00;

    // Normal memory, inner and outer non-cacheable
    const memory_uncacheable_encoding = 0b0100_0100;

    // Normal memory inner and outer writethrough, non-transient
    const memory_writethrough_encoding = 0b1011_1011;

    // Normal memory, inner and outer write-back, non-transient
    const memory_write_back_encoding = 0b1111_1111;

    return struct {
        // The value of the MAIR itself
        value: mair_value,

        // Cache the indices for each memory type
        device_uncacheable: ?mair_index,
        device_write_combining: ?mair_index,
        memory_uncacheable: ?mair_index,
        memory_writethrough: ?mair_index,
        memory_write_back: ?mair_index,

        pub fn init_from_mair_value(value: mair_value) @This() {
            return .{
                .value = value,
                .device_uncacheable = find_mair_index(value, device_uncacheable_encoding),
                .device_write_combining = find_mair_index(value, device_write_combining_encoding),
                .memory_uncacheable = find_mair_index(value, memory_uncacheable_encoding),
                .memory_writethrough = find_mair_index(value, memory_writethrough_encoding),
                .memory_write_back = find_mair_index(value, memory_write_back_encoding),
            };
        }

        fn encoding_at_index(value: mair_value, idx: mair_index) mair_encoding {
            return @truncate(u8, value >> (@as(u6, idx) * 8));
        }

        fn memory_type_at_index(self: *const @This(), idx: mair_index) MemoryType {
            const val = encoding_at_index(self.value, idx);
            return switch (val) {
                device_uncacheable_encoding => .DeviceUncacheable,
                device_write_combining_encoding => .DeviceWriteCombining,
                memory_uncacheable_encoding => .MemoryUncacheable,
                memory_writethrough_encoding => .MemoryWritethrough,
                memory_write_back_encoding => .MemoryWriteBack,
                else => {
                    log(null, "Index: {d}, value = 0x{X}", .{ idx, val });
                    @panic("Unknown MAIR value!");
                },
            };
        }

        fn find_mair_index(pat: mair_value, enc: mair_encoding) ?mair_index {
            var idx: mair_index = 0;
            while (true) : (idx += 1) {
                if (encoding_at_index(pat, idx) == enc)
                    return idx;

                if (idx == 7)
                    return null;
            }
        }

        pub fn find_memtype(self: *const @This(), memtype: MemoryType) ?mair_index {
            var idx: mair_index = 0;
            while (true) : (idx += 1) {
                if (self.memory_type_at_index(idx) == memtype)
                    return idx;

                if (idx == 7)
                    return null;
            }
        }

        pub fn get_active() @This() {
            return init_from_mair_value(MAIR.read());
        }

        pub fn make_default() @This() {
            const default = comptime init_from_mair_value(0 | memory_write_back_encoding << 0 | device_write_combining_encoding << 8 | memory_writethrough_encoding << 16 | device_uncacheable_encoding << 24 | memory_uncacheable_encoding << 32);
            return default;
        }
    };
}

const SCTLR = os.platform.msr(u64, "SCTLR_EL1");
const TCR = os.platform.msr(u64, "TCR_EL1");
const ID_AA64MMFR0 = os.platform.msr(u64, "ID_AA64MMFR0_EL1");

const Half = enum {
    Upper,
    Lower,
};

fn half(vaddr: u64) Half {
    if (std.math.maxInt(u64) / 2 < vaddr)
        return .Upper;
    return .Lower;
}

const PageSizeContext = struct {
    extrabits: u2,

    pub fn get_active(h: Half, tcr: u64) @This() {
        const val = switch (h) {
            .Upper => @truncate(u5, tcr >> 16),
            .Lower => @truncate(u5, tcr),
        };
        return switch (val) {
            0 => .{ .extrabits = 2 },
            8 => .{ .extrabits = 1 },
            16 => .{ .extrabits = 0 },
            else => @panic("Unknown paging mode!"),
        };
    }

    pub fn offset_bits(self: *const @This()) u64 {
        return switch (self.extrabits) {
            0 => 16,
            1 => 8,
            2 => 0,
            3 => @panic("3 extrabits??"),
        };
    }

    pub fn granule(self: *const @This(), h: Half) u64 {
        switch (self.extrabits) {
            0 => if (h == .Upper) return 0b10 else return 0b00,
            1 => if (h == .Upper) return 0b01 else return 0b10,
            2 => if (h == .Upper) return 0b11 else return 0b01,
            3 => @panic("3 extrabits??"),
        }
    }

    pub fn make_default() @This() {
        const id = ID_AA64MMFR0.read();

        if (((id >> 28) & 0x0F) == 0b0000) return .{ .extrabits = 0 };
        if (((id >> 20) & 0x0F) == 0b0001) return .{ .extrabits = 1 };
        if (((id >> 24) & 0x0F) == 0b0000) return .{ .extrabits = 2 };

        @panic("Cannot find valid page size");
    }

    pub fn basebits(self: *const @This()) u6 {
        return 9 + @as(u6, self.extrabits) * 2;
    }

    pub fn firstbits(self: *const @This()) u6 {
        // log2(@sizeOf(PTE)) = log2(8) = 3
        return self.basebits() + 3;
    }

    pub fn page_size(self: *const @This(), level: u6) usize {
        return @as(usize, 1) << self.firstbits() + self.basebits() * level;
    }
};

const ttbr_value = u64;
const ttbr0 = os.platform.msr(ttbr_value, "TTBR0_EL1");
const ttbr1 = os.platform.msr(ttbr_value, "TTBR1_EL1");
const level_type = u3;

pub fn make_page_table() !u64 {
    const pt = try os.memory.pmm.allocPhys(page_sizes[0]);
    const pt_bytes = os.platform.phys_slice(u8).init(pt, page_sizes[0]);
    @memset(pt_bytes.to_slice_writeback().ptr, 0x00, page_sizes[0]);
    return pt;
}

var pszc: PageSizeContext = undefined;

pub fn init() void {
    pszc = PageSizeContext.make_default();
    switch (pszc.page_size(0)) {
        0x1000 => {
            page_sizes = pages_4K[0..];
        },

        0x4000 => {
            page_sizes = pages_16K[0..];
        },

        0x10000 => {
            page_sizes = pages_64K[0..];
        },

        else => unreachable,
    }
}

pub fn page_size(level: u6) usize {
    return pszc.page_size(level);
}

pub const PagingContext = struct {
    mair: MAIRContext(),
    br0: u64,
    br1: u64,

    wb_virt_base: u64 = undefined,
    wc_virt_base: u64 = undefined,
    uc_virt_base: u64 = undefined,
    max_phys: u64 = undefined,

    pub fn apply(self: *@This()) void {
        var aa64mmfr0 = ID_AA64MMFR0.read();

        aa64mmfr0 &= 0x0F;
        if (aa64mmfr0 > 5)
            aa64mmfr0 = 5;

        // Make sure MMU is enabled
        const sctlr: u64 = 0x100D;

        // zig fmt: off
        const tcr: u64 = 0 | pszc.offset_bits() // T0SZ
            | pszc.offset_bits() << 16 // T1SZ
            | (1 << 8) // TTBR0 Inner WB RW-Allocate
            | (1 << 10) // TTBR0 Outer WB RW-Allocate
            | (1 << 24) // TTBR1 Inner WB RW-Allocate
            | (1 << 26) // TTBR1 Outer WB RW-Allocate
            | (2 << 12) // TTBR0 Inner shareable
            | (2 << 28) // TTBR1 Inner shareable
            | (aa64mmfr0 << 32) // intermediate address size
            | (pszc.granule(.Lower) << 14) // TTBR0 granule
            | (pszc.granule(.Upper) << 30) // TTBR1 granule
            | (1 << 56) // Fault on TTBR1 access from EL0
            | (0 << 55) // Don't fault on TTBR0 access from EL0
        ;
        // zig fmt: on

        asm volatile (
        // First, make sure we're not
        // doing this on a page boundary
            \\  .balign 0x20
            \\  MSR TCR_EL1,   %[tcr]
            \\  MSR SCTLR_EL1, %[sctlr]
            \\  MSR TTBR0_EL1, %[ttbr0]
            \\  MSR TTBR1_EL1, %[ttbr1]
            \\  MSR MAIR_EL1,  %[mair]
            \\  TLBI VMALLE1
            \\  DSB ISH
            \\  ISB
            :
            : [tcr] "r" (tcr),
              [sctlr] "r" (sctlr),
              [ttbr0] "r" (self.br0),
              [ttbr1] "r" (self.br1),
              [mair] "r" (self.mair.value)
        );
    }

    pub fn read_current() void {
        const tcr = TCR.read();

        const curr = &os.memory.paging.kernel_context;

        curr.mair = MAIRContext().get_active();
        curr.br0 = ttbr0.read();
        curr.br1 = ttbr1.read();

        const upper = PageSizeContext.get_active(.Upper, tcr);
        const lower = PageSizeContext.get_active(.Lower, tcr);

        if (lower.basebits() != upper.basebits())
            @panic("Cannot use different page sizes in upper/lower half!");
    }

    pub fn make_default() !@This() {
        // 32TB ought to be enough for anyone...
        const max_phys = 0x200000000000;

        const curr_base = os.memory.paging.kernel_context.wb_virt_base;

        return @This(){
            .mair = MAIRContext().make_default(),
            .br0 = try make_page_table(),
            .br1 = try make_page_table(),
            .wb_virt_base = curr_base,
            .wc_virt_base = curr_base + max_phys,
            .uc_virt_base = curr_base + max_phys * 2,
            .max_phys = max_phys,
        };
    }

    pub fn make_userspace() !@This() {
        var result = os.memory.paging.kernel_context;
        result.br0 = try make_page_table();
        errdefer result.deinit();

        return result;
    }

    pub fn deinit(self: *@This()) void {
        log(.err, "TODO: PagingContext deinit", .{});
    }

    pub fn can_map_at_level(self: *const @This(), level: level_type) bool {
        return page_sizes[level] < 0x1000000000;
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
        const h = half(virt);
        return .{
            .phys = if (h == .Lower) self.br0 else self.br1,
            .curr_level = 4,
            .context = self,
            .perms = os.memory.paging.rwx(),
            .underlying = null,
        };
    }

    fn decode(self: *@This(), enc: *EncodedPTE, level: level_type) PTE {
        var pte = PTEEncoding{ .raw = enc.* };

        if (!pte.present.read())
            return .Empty;
        if (pte.walk.read() and level != 0)
            return .{ .Table = self.decode_table(enc, level) };
        return .{ .Mapping = self.decode_mapping(enc, level) };
    }

    fn decode_mapping(self: *@This(), enc: *EncodedPTE, level: level_type) MappingPTE {
        const map = MappingEncoding{ .raw = enc.* };

        const memtype: MemoryType = self.mair.memory_type_at_index(map.attr_index.read());

        return .{
            .context = self,
            .phys = enc.* & phys_bitmask,
            .level = level,
            .memtype = memtype,
            .underlying = @ptrCast(*MappingEncoding, enc),
            .perms = .{
                .writable = !map.no_write.read(),
                .executable = !map.uxn_or_xn.read(),
                .userspace = map.user.read(),
            },
        };
    }

    fn decode_table(self: *@This(), enc: *EncodedPTE, level: level_type) TablePTE {
        const tbl = TableEncoding{ .raw = enc.* };

        return .{
            .context = self,
            .phys = enc.* & phys_bitmask,
            .curr_level = level,
            .underlying = @ptrCast(*TableEncoding, enc),
            .perms = .{
                .writable = !tbl.no_write.read(),
                .executable = !tbl.uxn_or_xn.read(),
                .userspace = !tbl.no_user.read(),
            },
        };
    }

    pub fn encode_empty(self: *const @This(), level: level_type) EncodedPTE {
        return 0;
    }

    pub fn encode_table(self: *const @This(), pte: TablePTE) !EncodedPTE {
        var tbl = TableEncoding{ .raw = pte.phys };

        tbl.present.write(true);
        tbl.walk.write(true);

        tbl.nonsecure.write(false);

        tbl.no_write.write(!pte.perms.writable);
        tbl.uxn_or_xn.write(!pte.perms.executable);
        tbl.no_user.write(!pte.perms.userspace);

        // We don't want to ever execute something userspace, and it's res0 if user is 0
        tbl.pxn.write(pte.perms.userspace);

        return tbl.raw;
    }

    pub fn encode_mapping(self: *const @This(), pte: MappingPTE) !EncodedPTE {
        var map = MappingEncoding{ .raw = pte.phys };

        map.present.write(true);
        map.access.write(true);
        map.nonsecure.write(false);
        map.walk.write(pte.level == 0);

        map.no_write.write(!pte.perms.writable);
        map.uxn_or_xn.write(!pte.perms.executable);
        map.user.write(pte.perms.userspace);

        // We don't want to ever execute something userspace, and it's res0 if user is 0
        map.pxn.write(pte.perms.userspace);

        map.shareability.write(2);

        const attr_idx = self.mair.find_memtype(pte.memtype.?) orelse @panic("Could not find MAIR index");
        map.attr_index.write(attr_idx);

        return map.raw;
    }

    pub fn domain(self: *const @This(), level: level_type, virtaddr: u64) os.platform.virt_slice {
        return .{
            .ptr = virtaddr & ~(page_sizes[level] - 1),
            .len = page_sizes[level],
        };
    }

    pub fn invalidate(self: *const @This(), virt: u64) void {
        asm volatile (
            \\TLBI VAE1, %[virt]
            :
            : [virt] "r" (virt >> pszc.basebits())
            : "memory"
        );
    }

    pub fn invalidateOtherCPUs(self: *const @This(), virt: usize, size: usize) void {
        log(.err, "idfk we should probably invalidate tlbs here on other cpus, but I think we've just been played for absolute fools", .{});
    }
};

pub const MemoryType = enum {
    DeviceUncacheable,
    DeviceWriteCombining,
    MemoryUncacheable,
    MemoryWritethrough,
    MemoryWriteBack,
};

const phys_bitmask = 0x0000FFFFFFFFF000;
const bf = lib.util.bitfields;

const PTEEncoding = extern union {
    raw: u64,

    present: bf.Boolean(u64, 0),
    walk: bf.Boolean(u64, 1),
};

const MappingEncoding = extern union {
    raw: u64,

    present: bf.Boolean(u64, 0),
    walk: bf.Boolean(u64, 1),
    attr_index: bf.Bitfield(u64, 2, 3),
    nonsecure: bf.Boolean(u64, 5),
    user: bf.Boolean(u64, 6),
    no_write: bf.Boolean(u64, 7),
    shareability: bf.Bitfield(u64, 8, 2),
    access: bf.Boolean(u64, 10),
    pxn: bf.Boolean(u64, 53),
    uxn_or_xn: bf.Boolean(u64, 54),
};

const TableEncoding = extern union {
    raw: u64,

    present: bf.Boolean(u64, 0),
    walk: bf.Boolean(u64, 1),
    pxn: bf.Boolean(u64, 59),
    uxn_or_xn: bf.Boolean(u64, 60),
    no_user: bf.Boolean(u64, 61),
    no_write: bf.Boolean(u64, 62),
    nonsecure: bf.Boolean(u64, 63),
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
    curr_level: level_type,
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

    pub fn level(self: *const @This()) level_type {
        return self.curr_level;
    }

    pub fn addPerms(self: *const @This(), perms: os.memory.paging.Perms) void {
        if (perms.executable)
            self.underlying.?.uxn_or_xn.write(false);
        if (perms.writable)
            self.underlying.?.no_write.write(false);
        if (perms.userspace)
            self.underlying.?.no_user.write(false);
        if (!perms.userspace and perms.executable)
            self.underlying.?.pxn.write(false);
    }

    pub fn make_child_table(self: *const @This(), enc: *u64, perms: os.memory.paging.Perms) !TablePTE {
        const pmem = try make_page_table();
        errdefer os.memory.pmm.freePhys(pmem, page_sizes[0]);

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
        const psz = page_sizes[self.level() - 1];
        const pmem = phys orelse try os.memory.pmm.allocPhys(psz);
        errdefer if (phys == null) os.memory.pmm.freePhys(pmem, psz);

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

pub const PTE = union(paging_common.PTEType) {
    Mapping: MappingPTE,
    Table: TablePTE,
    Empty: EmptyPte,
};
