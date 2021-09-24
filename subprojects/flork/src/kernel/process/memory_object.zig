usingnamespace @import("root").preamble;

const heap = os.memory.pmm.phys_heap;
const platform = os.platform;
const PagingContext = platform.paging.PagingContext;

const address_space = os.kernel.process.address_space;

const MemoryObjectRegionVtab: address_space.MemoryRegionVtable = .{
    .pageFault = MemoryObjectRegion.pageFault,
    //.dup = MemoryObjectRegion.dup,
};

fn pageSize() usize {
    return os.platform.paging.page_sizes[0];
}

const MemoryObjectRegion = struct {
    region: address_space.MemoryRegion = .{
        .vtab = &MemoryObjectRegionVtab,
    },

    memobj: *MemoryObject,
    page_perms: os.memory.paging.Perms,

    fn pageFault(
        region: *address_space.MemoryRegion,
        offset: usize,
        present: bool,
        fault_type: platform.PageFaultAccess,
        page_table: *PagingContext,
    ) address_space.PageFaultError!void {
        const self = @fieldParentPtr(@This(), "region", region);

        // If this was an access fault, and not a non-present entry, don't handle it
        if (present)
            return error.RangeRefusedHandling;

        const physmem = os.memory.pmm.allocPhys(pageSize()) catch |err| {
            switch (err) {
                error.PhysAllocTooSmall => unreachable,
                else => |q| return q,
            }
        };
        errdefer os.memory.pmm.freePhys(physmem, pageSize());

        const page_aligned_offset = lib.util.libalign.alignDown(usize, pageSize(), offset);

        {
            const phys_ptr = os.platform.phys_ptr([*]u8).from_int(physmem);
            var source_data = self.memobj.data[page_aligned_offset..];

            if (source_data.len > pageSize())
                source_data.len = pageSize();

            const data_dest = phys_ptr.get_writeback()[0..pageSize()];

            std.mem.copy(u8, data_dest, source_data);
            if (source_data.len < pageSize()) {
                std.mem.set(u8, data_dest[source_data.len..], 0);
            }
        }

        const vaddr = region.base + page_aligned_offset;

        os.memory.paging.mapPhys(.{
            .context = page_table,
            .virt = vaddr,
            .phys = physmem,
            .size = pageSize(),
            .perm = os.memory.paging.user(self.page_perms),
            .memtype = .MemoryWriteBack,
        }) catch |err| {
            switch (err) {
                error.IncompleteMapping, error.PhysAllocTooSmall => unreachable,
                error.AlreadyPresent, error.BadAlignment => return error.InternalError,
                error.OutOfMemory => return error.OutOfMemory,
            }
        };
    }

    fn dup(region: *address_space.MemoryRegion) !*address_space.MemoryRegion {
        const self = @fieldParentPtr(@This(), "region", region);
        const new = try heap.create(@This());
        errdefer heap.destroy(new);

        self.memobj.addRef();
        errdefer {
            if (self.removeRef()) {
                unreachable;
            }
        }

        new.* = .{
            .memobj = self.memobj,
        };

        return &new.region;
    }
};

pub const MemoryObject = struct {
    data: []const u8,
    refcount: usize,
    page_perms: os.memory.paging.Perms,

    pub fn makeRegion(self: *@This()) !*address_space.MemoryRegion {
        const region = try heap.create(MemoryObjectRegion);
        errdefer heap.destroy(region);

        region.* = .{
            .memobj = self,
            .page_perms = self.page_perms,
        };

        self.addRef();
        errdefer {
            if (self.removeRef()) {
                unreachable;
            }
        }

        return &region.region;
    }

    fn addRef(self: *@This()) void {
        _ = @atomicRmw(usize, &self.refcount, .Add, 1, .AcqRel);
    }

    fn removeRef(self: *@This()) bool {
        return @atomicRmw(usize, &self.refcount, .Sub, 1, .AcqRel) == 1;
    }
};

pub fn staticMemoryObject(data: []const u8, page_perms: os.memory.paging.Perms) MemoryObject {
    return .{
        .data = data,
        .refcount = 1, // Permanent 1 reference for keeping alive
        .page_perms = page_perms,
    };
}

const LazyZeroRegionVtab: address_space.MemoryRegionVtable = .{
    .pageFault = LazyZeroRegion.pageFault,
    //.dup = LazyZeroRegion.dup,
};

const LazyZeroRegion = struct {
    region: address_space.MemoryRegion = .{
        .vtab = &LazyZeroRegionVtab,
    },
    page_perms: os.memory.paging.Perms,

    fn pageFault(
        region: *address_space.MemoryRegion,
        offset: usize,
        present: bool,
        fault_type: platform.PageFaultAccess,
        page_table: *PagingContext,
    ) address_space.PageFaultError!void {
        const self = @fieldParentPtr(@This(), "region", region);

        // If this was an access fault, and not a non-present entry, don't handle it
        if (present)
            return error.RangeRefusedHandling;

        const physmem = os.memory.pmm.allocPhys(pageSize()) catch |err| {
            switch (err) {
                error.PhysAllocTooSmall => unreachable,
                else => |q| return q,
            }
        };
        errdefer os.memory.pmm.freePhys(physmem, pageSize());

        {
            const phys_ptr = os.platform.phys_ptr([*]u8).from_int(physmem);
            std.mem.set(u8, phys_ptr.get_writeback()[0..pageSize()], 0);
        }

        const vaddr = lib.util.libalign.alignDown(usize, pageSize(), region.base + offset);

        os.memory.paging.mapPhys(.{
            .context = page_table,
            .virt = vaddr,
            .phys = physmem,
            .size = pageSize(),
            .perm = os.memory.paging.user(self.page_perms),
            .memtype = .MemoryWriteBack,
        }) catch |err| {
            switch (err) {
                error.IncompleteMapping, error.PhysAllocTooSmall => unreachable,
                error.AlreadyPresent, error.BadAlignment => return error.InternalError,
                error.OutOfMemory => return error.OutOfMemory,
            }
        };
    }

    fn dup(region: *address_space.MemoryRegion) !*address_space.MemoryRegion {
        const self = @fieldParentPtr(@This(), "region", region);
        const new = try heap.create(@This());
        errdefer heap.destroy(new);

        self.memobj.addRef();
        errdefer {
            if (self.removeRef()) {
                unreachable;
            }
        }

        new.* = .{
            .memobj = self.memobj,
        };

        return &new.region;
    }
};

const LazyZeroes = struct {
    page_perms: os.memory.paging.Perms,

    pub fn makeRegion(self: *@This()) !*address_space.MemoryRegion {
        const region = try heap.create(LazyZeroRegion);
        errdefer heap.destroy(region);
        region.* = .{ .page_perms = self.page_perms };
        return &region.region;
    }
};

pub fn lazyZeroes(page_perms: os.memory.paging.Perms) LazyZeroes {
    return .{ .page_perms = page_perms };
}
