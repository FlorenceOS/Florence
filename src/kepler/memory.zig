const std = @import("std");
const os = @import("root").os;
const pmm = os.memory.pmm;
const vmm = os.memory.vmm;
const paging = os.memory.paging;
const platform = os.platform;

// Shared memory object
pub const MemoryObject = struct {
    frames: []usize,
    ref_count: usize,
    allocator: *std.mem.Allocator,
    page_size: usize,

    pub fn create(allocator: *std.mem.Allocator, size: usize) !*MemoryObject {
        const instance = try allocator.create(@This());
        instance.ref_count = 1;
        instance.allocator = allocator;
        errdefer allocator.destroy(instance);

        std.debug.assert(platform.page_sizes.len > 0);
        const page_size = platform.page_sizes[0];
        const page_count = os.lib.libalign.align_up(usize, size, page_size) / page_size;
        instance.page_size = page_size;

        instance.frames = try allocator.alloc(usize, page_count);
        errdefer allocator.free(instance.frames);

        for (instance.frames) |*page, i| {
            page.* = pmm.alloc_phys(page_size) catch |err| {
                for (instance.frames[0..i]) |*page_to_dispose| {
                    pmm.free_phys(page_to_dispose.*, page_size);
                }
                return err;
            };
        }

        return instance;
    }

    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.ref_count, .Add, 1, .AcqRel);
        return self;
    }

    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.ref_count, .Sub, 1, .AcqRel) > 1) {
            return;
        }
        for (self.frames[0..self.frames.len]) |*page| {
            pmm.free_phys(page.*, self.page_size);
        }
        self.allocator.free(self.frames);
        self.allocator.destroy(self);
    }

    /// Size in virtual memory
    pub fn virtual_size(self: *const @This()) usize {
        return self.frames.len * self.page_size;
    }
};

/// Shared memory mapper interface
pub const Mapper = struct {
    /// Map errors
    pub const Error = error{
        OutOfVirtualMemory,
        MappingFailure,
    };
    /// Callback to map shared memory object. Reference is already borrowed
    map_impl: fn (self: *@This(), object: *const MemoryObject, perms: paging.Perms, memtype: platform.paging.MemoryType) Error!usize,
    /// Callback to unmap shared memory object. Reference is not dropped
    unmap_impl: fn (self: *@This(), object: *const MemoryObject, addr: usize) void,

    // Wrappers to make things a little bit nicer
    /// Map shared memory object. Reference is already borrowed
    pub fn map(self: *@This(), object: *const MemoryObject, perms: paging.Perms, memtype: platform.paging.MemoryType) !usize {
        return self.map_impl(self, object, perms, memtype);
    }

    /// Unmap shared memory object. Reference is not dropped
    pub fn unmap(self: *@This(), object: *const MemoryObject, addr: usize) void {
        return self.unmap_impl(self, object, addr);
    }
};

/// Map memory object in the kernel virtual address space
fn map_obj_in_kernel(_: *Mapper, object: *const MemoryObject, perms: paging.Perms, memtype: platform.paging.MemoryType) Mapper.Error!usize {
    // Allocate non-backed memory
    const fake_arr = vmm.nonbacked_range.allocator.allocFn(&vmm.nonbacked_range.allocator, object.virtual_size(), 1, 1, 0) catch return error.OutOfVirtualMemory;
    errdefer _ = vmm.nonbacked_range.allocator.resizeFn(&vmm.nonbacked_range.allocator, fake_arr, 1, 0, 1, 0) catch unreachable;
    // Map pages
    const base = @ptrToInt(fake_arr.ptr);
    var i: usize = 0;
    while (i < object.frames.len) : (i += 1) {
        const virt = base + i * object.page_size;
        const phys = object.frames[i];
        const size = object.page_size;
        errdefer paging.unmap(.{ .virt = base, .size = size * i, .reclaim_pages = false });
        paging.map_phys(.{ .virt = virt, .phys = phys, .size = size, .perm = perms, .memtype = memtype }) catch return error.MappingFailure;
    }
    return base;
}

/// Unmap memory object from the kernel virtual address space
pub fn unmap_obj_in_kernel(_: *Mapper, object: *const MemoryObject, addr: usize) void {
    const fake_arr = @intToPtr([*]u8, addr)[0..object.virtual_size()];
    paging.unmap(.{ .virt = addr, .size = object.virtual_size(), .reclaim_pages = false });
    _ = vmm.nonbacked_range.allocator.resizeFn(&vmm.nonbacked_range.allocator, fake_arr, 1, 0, 1, 0) catch unreachable;
}

/// Exposed mapper inteface for the kernel arena
pub var kernel_mapper = Mapper{
    .map_impl = map_obj_in_kernel,
    .unmap_impl = unmap_obj_in_kernel,
};
