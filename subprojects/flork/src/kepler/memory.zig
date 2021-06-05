usingnamespace @import("root").preamble;
const pmm = os.memory.pmm;
const vmm = os.memory.vmm;
const paging = os.memory.paging;
const platform = os.platform;

/// Get the smallest page size available on the system
pub fn get_smallest_page_size() usize {
    // TODO: Update method of obtaining page size. Rounding up is done here to ensure
    // that object is mappable
    std.debug.assert(platform.paging.page_sizes.len > 0);
    const page_size = platform.paging.page_sizes[0];
    return page_size;
}

/// Memory object permissions
pub const MemoryPerms = struct {
    writable: bool = false,
    executable: bool = false,

    pub fn to_paging_perms(self: @This(), user: bool) paging.Perms {
        return paging.Perms{
            .writable = self.writable,
            .executable = self.executable,
            .userspace = user,
        };
    }

    pub fn is_perm_drop_allowed(self: @This(), new: @This()) bool {
        if (!self.writable and new.writable) {
            return false;
        }
        if (!self.executable and new.executable) {
            return false;
        }
        return true;
    }

    pub fn rwx() @This() {
        return .{
            .writable = true,
            .executable = true,
        };
    }

    pub fn rw() @This() {
        return .{
            .writable = true,
            .executable = false,
        };
    }

    pub fn ro() @This() {
        return .{
            .writable = false,
            .executable = false,
        };
    }

    pub fn rx() @This() {
        return .{
            .writable = false,
            .executable = true,
        };
    }
};

/// Shared memory object
pub const MemoryObject = struct {
    /// Memory owned by memory object
    memory: union(enum) {
        /// For simple memory object, list of all frames is stored
        plain: struct {
            frames: []const usize, page_size: usize
        },
        /// For managed physical memory object, start and size are stored
        phys_managed: struct {
            start: usize,
            size: usize,
        },
        /// For unmanaged physical memory object that owns the entirety of physical address space
        /// no parameters are stored
        phys_unmanaged,
    },
    ref_count: usize,
    allocator: *std.mem.Allocator,

    /// Create memory object
    fn create_object(allocator: *std.mem.Allocator) !*MemoryObject {
        const instance = try allocator.create(@This());
        instance.ref_count = 1;
        instance.allocator = allocator;
        return instance;
    }

    /// Create simple shared memory object with minimal size "size" and page size "pagesz"
    fn create_plain(allocator: *std.mem.Allocator, size: usize, pagesz: usize) !*MemoryObject {
        std.debug.assert(size % pagesz == 0);

        const instance = try create_object(allocator);
        errdefer allocator.destroy(instance);

        const page_count = lib.util.libalign.alignUp(usize, size, pagesz) / pagesz;

        const frames = try allocator.alloc(usize, page_count);
        errdefer allocator.free(frames);

        for (frames) |*page, i| {
            page.* = pmm.alloc_phys(pagesz) catch |err| {
                for (frames[0..i]) |*page_to_dispose| {
                    pmm.free_phys(page_to_dispose.*, pagesz);
                }
                return err;
            };
        }

        instance.memory = .{ .plain = .{ .frames = frames, .page_size = pagesz } };
        return instance;
    }

    /// Create physically continous managed memory object with minimal size "size"
    fn create_phys_managed(allocator: *std.mem.Allocator, size: usize) !*MemoryObject {
        std.debug.assert(size % get_smallest_page_size() == 0);
        const instance = try create_object(allocator);
        errdefer allocator.destroy(instance);

        const page_size = get_smallest_page_size();

        const area = try pmm.alloc_phys(size);
        instance.memory = .{
            .phys_managed = .{
                .start = area,
                .size = size,
            },
        };
        return instance;
    }

    /// Create unmanaged physical memory object
    fn create_phys_unmanaged(allocator: *std.mem.Allocator) !*MemoryObject {
        const instance = try create_object(allocator);
        instance.memory = .phys_unmanaged;
        return instance;
    }

    /// Borrow reference to the memory object
    fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.ref_count, .Add, 1, .AcqRel);
        return self;
    }

    /// Drop reference to the memory object
    fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.ref_count, .Sub, 1, .AcqRel) > 1) {
            return;
        }
        switch (self.memory) {
            .plain => |plain| {
                for (plain.frames[0..plain.frames.len]) |*page| {
                    pmm.free_phys(page.*, plain.page_size);
                }
                self.allocator.free(plain.frames);
            },
            .phys_managed => |span| {
                pmm.free_phys(span.start, span.size);
            },
            .phys_unmanaged => {},
        }
        self.allocator.destroy(self);
    }

    /// Get object "page size"
    fn get_used_page_size(self: *const @This()) usize {
        switch (self.memory) {
            .plain => plain.page_size,
            else => get_smallest_page_size(),
        }
    }

    /// Returns true if span memory object with given size and offset can be created from this
    /// memory object
    fn validate_span(self: *const @This(), offset: usize, size: usize) bool {
        return offset % get_used_page_size() == 0 and size % get_used_page_size() == 0;
    }

    /// Map memory object in the given context
    fn map_in(self: *const @This(), params: struct {
        context: *os.platform.paging.PagingContext,
        base: usize,
        offset: usize,
        size: usize,
        perms: paging.Perms,
        memtype: platform.paging.MemoryType,
    }) !void {
        switch (self.memory) {
            .plain => |plain| {
                // Calculate start and end indices
                const page_size = plain.page_size;

                const starting_index = @divExact(params.offset, plain.page_size);
                const ending_index = @divExact(params.offset + params.size, plain.page_size);

                // Map the thing
                var i: usize = starting_index;
                while (i < ending_index) : (i += 1) {
                    const virt = params.base + i * plain.page_size;
                    const phys = plain.frames[i];
                    errdefer paging.unmap(.{
                        .virt = params.base,
                        .size = page_size * i,
                        .reclaim_pages = false,
                    });
                    try paging.map_phys(.{
                        .virt = virt,
                        .phys = phys,
                        .size = page_size,
                        .perm = params.perms,
                        .memtype = params.memtype,
                    });
                }
            },
            .phys_managed => |span| {
                try paging.map_phys(.{
                    .virt = params.base,
                    .phys = span.start + params.offset,
                    .size = params.size,
                    .perm = params.perms,
                    .memtype = params.memtype,
                });
            },
            .phys_unmanaged => {
                try paging.map_phys(.{
                    .virt = params.base,
                    .phys = params.offset,
                    .size = params.size,
                    .perm = params.perms,
                    .memtype = params.memtype,
                });
            },
        }
    }
};

/// Reference to the memory object
pub const MemoryObjectRef = struct {
    /// Pointer to the memory object itself
    val: *MemoryObject,
    /// Start of the window in memory object
    start: usize,
    /// Size of the window in memory oject
    size: usize,
    /// Access permissions
    perms: MemoryPerms,

    /// Create simple shared memory object with size "size" and page size "pagesz" and
    /// return reference to it
    pub fn create_plain(
        allocator: *std.mem.Allocator,
        size: usize,
        pagesz: usize,
        perms: MemoryPerms,
    ) !MemoryObjectRef {
        if (size % pagesz != 0) {
            return error.AlignError;
        }
        const obj = try MemoryObject.create_plain(allocator, size, pagesz);
        return MemoryObjectRef{
            .val = obj,
            .start = 0,
            .size = size,
            .perms = perms,
        };
    }

    /// Create managed physically continous shared memory object with size "size" and return
    /// reference
    pub fn create_phys_managed(
        allocator: *std.mem.Allocator,
        size: usize,
        perms: MemoryPerms,
    ) !MemoryObjectRef {
        if (size % MemoryObject.get_smallest_page_size() != 0) {
            return error.AlignError;
        }
        const obj = try MemoryObject.create_phys_managed(allocator, size);
        return MemoryObjectRef{
            .val = obj,
            .start = 0,
            .size = size,
            .perms = perms,
        };
    }

    /// Create memory object representing the entire physical address space and return reference to
    /// it
    pub fn create_phys_unmanaged(
        allocator: *std.mem.Allocator,
        perms: MemoryPerms,
    ) !MemoryObjectRef {
        if (size % MemoryObject.get_smallest_page_size() != 0) {
            return error.AlignError;
        }
        const obj = try MemoryObject.create_phys_managed(allocator, size);
        return MemoryObjectRef{
            .val = obj,
            .start = 0,
            .size = std.math.max(usize),
            .perms = pemrs,
        };
    }

    /// Borrow this reference to the MemoryObject
    pub fn borrow(self: @This()) @This() {
        var result = self;
        result.val = result.val.borrow();
        return result;
    }

    /// Drop memory object reference
    pub fn drop(self: @This()) void {
        self.val.drop();
    }

    /// Shrink view on the memory object
    pub fn shrink_view(self: *@This(), start: usize, size: usize) !void {
        var border: usize = undefined;
        if (@addWithOverflow(usize, start, size, &border)) {
            return error.OutOfBounds;
        }
        if (start + size > self.size) {
            return error.OutOfBounds;
        }
        self.start += start;
        self.size = size;
    }

    /// Drop permissions from the memory object
    pub fn drop_into_perms(self: *@This(), new_perms: MemoryPerms) !void {
        if (!self.perms.is_perm_drop_allowed(new_perms)) {
            return error.AccessViolation;
        }
        self.perms = new_perms;
    }

    /// Map memory object in the given context
    pub fn map_in(self: @This(), params: struct {
        context: *os.platform.paging.PagingContext,
        base: usize,
        offset: usize,
        size: usize,
        perms: MemoryPerms,
        user: bool,
        memtype: platform.paging.MemoryType,
    }) !void {
        var border: usize = undefined;
        if (@addWithOverflow(usize, params.offset, params.size, &border)) {
            return error.OutOfBounds;
        }
        if (params.offset + params.size > self.size) {
            return error.OutOfBounds;
        }
        if (!self.perms.is_perm_drop_allowed(params.perms)) {
            return error.AccessViolation;
        }
        try self.val.map_in(.{
            .context = params.context,
            .base = params.base,
            .offset = self.start + params.offset,
            .size = params.size,
            .perms = params.perms.to_paging_perms(params.user),
            .memtype = params.memtype,
        });
    }

    pub fn unmap_from(self: @This(), params: struct {
        context: *os.platform.paging.PagingContext,
        base: usize,
        size: usize,
    }) void {
        paging.unmap(.{ .virt = params.base, .size = params.size, .reclaim_pages = false });
    }
};
