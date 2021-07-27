usingnamespace @import("root").preamble;

const rb = lib.containers.rbtree;
const platform = os.platform;
const PagingContext = platform.paging.PagingContext;

const rb_features: rb.Features = .{
    .enable_iterators_cache = true,
    .enable_kth_queries = false,
    .enable_not_associatve_augment = false,
};

const addr_config: rb.Config = .{
    .features = rb_features,
    .augment_callback = null,
    .comparator = AddressComparator,
};

const AddressComparator = struct {
    pub fn compare(self: *const @This(), left: *const MemoryRegion, right: *const MemoryRegion) bool {
        return left.base >= right.base;
    }
};

const RbNode = rb.Node(rb_features);
const RbTree = rb.Tree(MemoryRegion, "rb_node", addr_config);

pub const PageFaultError = error{
    RangeRefusedHandling,
    OutOfMemory,
    InternalError,
};

//pub const DupError = error{
//    OutOfMemory,
//    Refusing,
//};

pub const MemoryRegionVtable = struct {
    /// Call this on a page fault into the region, be it read, write or execute
    /// returns whether the page fault was handled by the region itself
    pageFault: fn (
        *MemoryRegion,
        offset: usize,
        present: bool,
        fault_type: platform.PageFaultAccess,
        page_table: *PagingContext,
    ) PageFaultError!void,

    // /// Call to duplicate a memory region, for fork or similar
    // dup: fn (*MemoryRegion) DupError!*MemoryRegion,
};

pub const MemoryRegion = struct {
    // TODO: rbtree node for this memory region
    rb_node: RbNode = undefined,

    // vtable with function pointers to implementations
    vtab: *const MemoryRegionVtable,

    /// The base address of the region
    base: usize = undefined,

    /// The byte size of the region
    size: usize = undefined,

    pub fn pageFault(
        self: *@This(),
        offset: usize,
        present: bool,
        fault_type: platform.PageFaultAccess,
        page_table: *PagingContext,
    ) !void {
        return self.vtab.pageFault(
            self,
            offset,
            present,
            fault_type,
            page_table,
        );
    }

    //pub fn dup(self: *@This()) !*MemoryRegion {
    //    return self.vtab.dup(self);
    //}

    pub fn contains(self: @This(), addr: usize) bool {
        return addr >= self.base and addr < self.base + self.size;
    }
};

fn pageSize() usize {
    return os.platform.paging.page_sizes[0];
}

pub const AddrSpace = struct {
    emptyRanges: os.memory.range_alloc.RangeAlloc = .{},
    usedRanges: RbTree = RbTree.init(.{}, {}),

    pub fn init(self: *@This(), base: usize, end: usize) !void {
        self.* = .{};
        try self.emptyRanges.giveRange(.{
            .base = base,
            .size = end - base,
        });
    }

    pub fn deinit(self: *@This()) !void {
        // TODO
        unreachable;
    }

    /// Try to allocate space at a specific address
    pub fn allocateAt(self: *@This(), addr: usize, size_in: usize) !void {
        if (!lib.util.libalign.isAligned(usize, pageSize(), addr))
            return error.AddrNotAligned;

        const size = lib.util.libalign.alignUp(usize, pageSize(), size_in);

        _ = try self.emptyRanges.allocateAt(addr, size);
    }

    /// Allocates new space anywhere in the address space
    pub fn allocateAnywhere(self: *@This(), size_in: usize) !usize {
        const size = lib.util.libalign.alignUp(usize, pageSize(), size_in);

        const r = try self.emptyRanges.allocateAnywhere(size, pageSize(), pageSize());

        return @ptrToInt(r.ptr);
    }

    pub fn findRangeAt(self: *@This(), addr: usize) ?*MemoryRegion {
        const addr_finder: struct {
            addr: usize,

            pub fn check(finder: *const @This(), region: *const MemoryRegion) bool {
                return region.base + region.size >= finder.addr;
            }
        } = .{ .addr = addr };

        var candidate = self.usedRanges.lowerBound(@TypeOf(addr_finder), &addr_finder);

        if (candidate) |c| {
            if (c.contains(addr))
                return c;
        }

        return null;
    }

    pub fn findRangeContaining(self: *@This(), addr: usize, size: usize) ?*MemoryRegion {
        if (findRangeAt(addr)) |range| {
            if (range.contains(addr + size - 1))
                return range;
        }
        return null;
    }

    pub fn pageFault(self: *@This(), addr: usize, present: bool, fault_type: platform.PageFaultAccess) !void {
        const range = self.findRangeAt(addr) orelse return error.NoRangeAtAddress;
        try range.pageFault(addr - range.base, present, fault_type, self.pageTable());
    }

    pub fn lazyMap(self: *@This(), addr: usize, size: usize, region: *MemoryRegion) !void {
        region.base = addr;
        region.size = size;
        self.usedRanges.insert(region);
    }

    pub fn freeAndUnmap(self: *@This(), addr: usize, size: usize) void {
        // TODO
        unreachable;
    }

    fn pageTable(self: *@This()) *PagingContext {
        return &@fieldParentPtr(os.kernel.process.Process, "addr_space", self).page_table;
    }
};
