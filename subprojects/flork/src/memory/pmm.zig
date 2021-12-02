const os = @import("root").os;
const std = @import("std");
const lib = @import("lib");

const log = lib.output.log.scoped(.{
    .prefix = "memory/pmm",
    .filter = .info,
}).write;

const assert = std.debug.assert;
const platform = os.platform;
const lalign = lib.util.libalign;

const pmm_sizes = {
    comptime var shift = 12;
    comptime var sizes: []const usize = &[0]usize{};

    while (shift < @bitSizeOf(usize) - 3) : (shift += 1) {
        sizes = sizes ++ [1]usize{1 << shift};
    }

    return sizes;
};

const reverse_sizes = {
    var result: [pmm_sizes.len]usize = undefined;
    for (pmm_sizes) |psz, i| {
        result[pmm_sizes.len - i - 1] = psz;
    }
    return result;
};

var free_roots = [_]usize{0} ** pmm_sizes.len;
var pmm_mutex = os.thread.Mutex{};

fn allocImpl(ind: usize) error{OutOfMemory}!usize {
    if (free_roots[ind] == 0) {
        if (ind + 1 >= pmm_sizes.len)
            return error.OutOfMemory;

        var next = try allocImpl(ind + 1);
        var next_size = pmm_sizes[ind + 1];

        const current_size = pmm_sizes[ind];

        while (next_size > current_size) {
            freeImpl(next, ind);
            next += current_size;
            next_size -= current_size;
        }

        return next;
    } else {
        const retval = free_roots[ind];
        const new_root = os.platform.phys_ptr(*usize).from_int(retval).get_writeback().*;

        if (std.debug.runtime_safety and !lalign.isAligned(usize, pmm_sizes[ind], new_root)) {
            log(null, "New root: 0x{X} at index {d} is bad, referenced by 0x{X}!", .{ free_roots[ind], ind, retval });
            @panic("Physical heap corrupted");
        }

        free_roots[ind] = new_root;
        return retval;
    }
}

fn freeImpl(phys: usize, ind: usize) void {
    const last = free_roots[ind];
    free_roots[ind] = phys;
    os.platform.phys_ptr(*usize).from_int(phys).get_writeback().* = last;
}

pub fn consume(phys: usize, size: usize) void {
    pmm_mutex.lock();
    defer pmm_mutex.unlock();

    var sz = size;
    var pp = phys;

    outer: while (sz != 0) {
        for (reverse_sizes) |psz, ri| {
            const i = pmm_sizes.len - ri - 1;
            if (sz >= psz and lalign.isAligned(usize, psz, pp)) {
                freeImpl(pp, i);
                sz -= psz;
                pp += psz;
                continue :outer;
            }
        }
        unreachable;
    }
}

pub fn allocPhys(size: usize) !usize {
    for (pmm_sizes) |psz, i| {
        if (size <= psz) {
            pmm_mutex.lock();
            defer pmm_mutex.unlock();
            return allocImpl(i);
        }
    }
    return error.PhysAllocTooSmall;
}

pub fn getAllocationSize(size: usize) usize {
    for (pmm_sizes) |psz, i| {
        if (size <= psz) {
            return psz;
        }
    }
    @panic("getAllocationSize");
}

pub fn freePhys(phys: usize, size: usize) void {
    pmm_mutex.lock();
    defer pmm_mutex.unlock();

    for (pmm_sizes) |psz, i| {
        if (size <= psz and lalign.isAligned(usize, psz, phys)) {
            return freeImpl(phys, i);
        }
    }
    unreachable;
}

const PhysAllocator = struct {
    allocator: std.mem.Allocator = .{
        .allocFn = allocFn,
        .resizeFn = resizeFn,
    },

    fn allocFn(alloc: *std.mem.Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) std.mem.Allocator.Error![]u8 {
        const alloc_len = getAllocationSize(len);

        const ptr = os.platform.phys_ptr([*]u8).from_int(allocPhys(alloc_len) catch |err| {
            switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    log(null, "PMM allocator: {e}", .{err});
                    @panic("PMM allocator allocation error");
                },
            }
        });

        return ptr.get_writeback()[0..len];
    }

    fn resizeFn(alloc: *std.mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, len_align: u29, ret_addr: usize) std.mem.Allocator.Error!usize {
        const old_alloc = getAllocationSize(old_mem.len);

        const addr = @ptrToInt(old_mem.ptr);
        const base_vaddr = @ptrToInt(os.platform.phys_ptr([*]u8).from_int(0).get_writeback());
        const paddr = addr - base_vaddr;

        if (new_size == 0) {
            freePhys(paddr, old_alloc);
            return 0;
        } else {
            const new_alloc = getAllocationSize(new_size);

            if (new_alloc > old_alloc)
                return error.OutOfMemory;

            var curr_alloc = old_alloc;
            while (new_alloc < curr_alloc) {
                freePhys(paddr + curr_alloc / 2, curr_alloc / 2);
                curr_alloc /= 2;
            }

            return new_size;
        }
    }
};

var phys_alloc = PhysAllocator{};
var phys_gpa = std.heap.GeneralPurposeAllocator(.{
    .thread_safe = true,
    .MutexType = os.thread.Mutex,
}){
    .backing_allocator = &phys_alloc.allocator,
};
pub const phys_heap = &phys_gpa.allocator;

export fn laihost_malloc(sz: usize) ?*c_void {
    if (sz == 0) return @intToPtr(*c_void, 0x1000);
    const mem = phys_heap.alloc(u8, sz) catch return os.kernel.lai.NULL;
    return @ptrCast(*c_void, mem.ptr);
}

export fn laihost_realloc(ptr: ?*c_void, newsize: usize, oldsize: usize) ?*c_void {
    if (oldsize == 0) {
        return laihost_malloc(newsize);
    }
    if (newsize == 0) {
        laihost_free(ptr, oldsize);
        return @intToPtr(*c_void, 0x1000);
    }
    const ret = laihost_malloc(newsize);
    @memcpy(@ptrCast([*]u8, ret), @ptrCast([*]const u8, ptr), oldsize);
    laihost_free(ptr, oldsize);
    return ret;
}

export fn laihost_free(ptr: ?*c_void, oldsize: usize) void {
    if (oldsize == 0 or ptr == null) return;
    phys_heap.free(@ptrCast([*]u8, ptr)[0..oldsize]);
}
