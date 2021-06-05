usingnamespace @import("root").preamble;

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

var free_roots = [_]usize{0} ** pmm_sizes.len;

var pmm_mutex = os.thread.Mutex{};

const reverse_sizes = {
    var result: [pmm_sizes.len]usize = undefined;
    for (pmm_sizes) |psz, i| {
        result[pmm_sizes.len - i - 1] = psz;
    }
    return result;
};

pub fn consume(phys: usize, size: usize) void {
    pmm_mutex.lock();
    defer pmm_mutex.unlock();

    var sz = size;
    var pp = phys;

    outer: while (sz != 0) {
        for (reverse_sizes) |psz, ri| {
            const i = pmm_sizes.len - ri - 1;
            if (sz >= psz and lalign.isAligned(usize, psz, pp)) {
                free_impl(pp, i);
                sz -= psz;
                pp += psz;
                continue :outer;
            }
        }
        unreachable;
    }
}

pub fn good_size(size: usize) usize {
    unreachable;
}

fn alloc_impl(ind: usize) error{OutOfMemory}!usize {
    if (free_roots[ind] == 0) {
        if (ind + 1 >= pmm_sizes.len)
            return error.OutOfMemory;

        var next = try alloc_impl(ind + 1);
        var next_size = pmm_sizes[ind + 1];

        const current_size = pmm_sizes[ind];

        while (next_size > current_size) {
            free_impl(next, ind);
            next += current_size;
            next_size -= current_size;
        }

        return next;
    } else {
        const retval = free_roots[ind];
        free_roots[ind] = os.platform.phys_ptr(*usize).from_int(retval).get_writeback().*;
        return retval;
    }
}

pub fn alloc_phys(size: usize) !usize {
    for (pmm_sizes) |psz, i| {
        if (size <= psz) {
            pmm_mutex.lock();
            defer pmm_mutex.unlock();
            return alloc_impl(i);
        }
    }
    return error.PhysAllocTooSmall;
}

fn free_impl(phys: usize, ind: usize) void {
    const last = free_roots[ind];
    free_roots[ind] = phys;
    os.platform.phys_ptr(*usize).from_int(phys).get_writeback().* = last;
}

pub fn free_phys(phys: usize, size: usize) void {
    pmm_mutex.lock();
    defer pmm_mutex.unlock();

    for (reverse_sizes) |psz, ri| {
        const i = pmm_sizes.len - ri - 1;

        if (size <= psz and lalign.isAligned(usize, psz, phys)) {
            return free_impl(phys, i);
        }
    }
    unreachable;
}

pub fn phys_to_uncached_virt(phys: usize) usize {
    return os.memory.paging.kernel_context.phys_to_uncached_virt(phys);
}

pub fn phys_to_write_combining_virt(phys: usize) usize {
    return os.memory.paging.kernel_context.phys_to_write_combining_virt(phys);
}

pub fn phys_to_write_back_virt(phys: usize) usize {
    return os.memory.paging.kernel_context.phys_to_write_back_virt(phys);
}
