const os = @import("root").os;

const Bitset = os.lib.bitset.Bitset;
const range = os.lib.range.range;

const assert = @import("std").debug.assert;

const paging = os.memory.paging;
const page_size = os.platform.page_sizes[0];

// O(1) worst case alloc() and free() buddy allocator I came up with (idk if anyone has done this before)
const free_node = struct {
    next: ?*@This() = null,
    prev: ?*@This() = null,

    pub fn remove(self: *@This()) void {
        assert(self.prev != null);

        if (self.next != null)
            self.next.?.prev = self.prev;

        self.prev.?.next = self.next;
    }
};

pub fn buddy_alloc(comptime allocator_size: usize, comptime minsize: usize) type {
    var curr_size = minsize;
    var allocator_levels = 1;

    while (curr_size != allocator_size) {
        allocator_levels += 1;
        curr_size <<= 1;
    }

    const num_entries_at_bottom_level = allocator_size / minsize;
    const bitset_sz = num_entries_at_bottom_level * 2 - 2;

    assert(@sizeOf(free_node) <= minsize);

    return struct {
        bs: Bitset(bitset_sz) = .{},
        freelists: [allocator_levels]free_node = [_]free_node{free_node{}} ** allocator_levels,
        inited: bool = false,
        base: usize,

        pub fn init(self: *@This(), base: usize) !void {
            if (self.inited)
                return error.AlreadyInited;

            self.inited = true;
            self.base = base;

            // Making up a new address here, need to make sure it's mapped
            const root_node = @intToPtr(*free_node, self.base);

            try paging.map(.{
                .virt = self.base,
                .size = page_size,
                .perm = paging.data(),
            });

            self.freelists[allocator_levels - 1].next = root_node;
            root_node.prev = &self.freelists[allocator_levels - 1];
            root_node.next = null;
        }

        pub fn deinit(self: *@This()) !void {
            if (!self.inited)
                return error.NotInited;

            if (!self.freelists[allocator_levels - 1].next != @intToPtr(*free_node, self.base))
                return error.CannotRollback;

            self.inited = false;
        }

        pub fn alloc_size(self: *@This(), size: usize) !usize {
            inline for (range(allocator_levels)) |lvl| {
                if (size <= level_size(lvl))
                    return self.alloc(lvl);
            }
            return error.OutOfMemory;
        }

        pub fn free_size(self: *@This(), size: usize, addr: usize) !void {
            inline for (range(allocator_levels)) |lvl| {
                if (size <= level_size(lvl))
                    return self.free(lvl, addr);
            }
            return error.BadSize;
        }

        fn level_size(comptime level: usize) usize {
            return minsize << level;
        }

        fn buddy_addr(comptime level: usize, addr: usize) usize {
            return addr ^ level_size(level);
        }

        fn addr_bitset_index(self: @This(), comptime level: usize, addr: usize) usize {
            var curr_step = num_entries_at_bottom_level;
            var idx: usize = 0;
            var block_size = minsize;

            inline for (range(level)) |lvl| {
                idx += curr_step;
                curr_step /= 2;
                block_size *= 2;
            }

            return idx + (addr - self.base) / block_size;
        }

        fn alloc(self: *@This(), comptime level: usize) !usize {
            if (self.freelists[level].next) |v| {
                // Hey, this thing on the freelist here looks as good as any.
                v.remove();
                return @ptrToInt(v);
            } else {
                if (level == allocator_levels - 1) {
                    return error.OutOfMemory;
                }

                const v = try self.alloc(level + 1);
                errdefer self.free(level + 1, v) catch unreachable;

                // Making up a new address here, need to make sure it's mapped
                const buddy = buddy_addr(level, v);

                paging.map(.{
                    .virt = buddy,
                    .size = page_size,
                    .perm = paging.data(),
                }) catch |err| switch (err) {
                    error.AlreadyPresent => {}, // That's fine to us.
                    else => return err,
                };

                errdefer paging.unmap(.{
                    .virt = buddy,
                    .size = page_size,
                    .perm = paging.data(),
                });

                self.add_free(buddy, level);
                return v;
            }
        }

        // Free something without checking for its buddy, !only! use when its buddy is !not! free
        fn add_free(self: *@This(), ptr: usize, comptime level: usize) void {
            // Insert into freelist
            const node = @intToPtr(*free_node, ptr);

            node.next = self.freelists[level].next;
            node.prev = &self.freelists[level];

            self.freelists[level].next = node;

            // Set bit in bitset
            self.bs.set(self.addr_bitset_index(level, ptr));
        }

        fn free(self: *@This(), comptime level: usize, addr: usize) !void {
            if (level == allocator_levels - 1) {
                // We're done, this is the top level
                self.add_free(addr, level);
                return;
            } else {
                const buddy = buddy_addr(level, addr);
                const buddy_index = self.addr_bitset_index(level, buddy);

                // Is buddy free??
                if (!self.bs.is_set(buddy_index)) {
                    // If not, just add this node to the freelist
                    self.add_free(addr, level);
                    return;
                }

                // Hey, it _is_ free
                const buddy_node = @intToPtr(*free_node, buddy);

                // The node has to be removed from the freelist
                // before it's unmapped, otherwise we can't read its contents.

                // Bubble it up
                if (addr < buddy) {
                    try self.free(level + 1, addr);

                    buddy_node.remove();

                    paging.unmap(.{
                        .virt = buddy,
                        .size = page_size,
                        .reclaim_pages = true,
                    }) catch unreachable;
                } else {
                    try self.free(level + 1, buddy);

                    buddy_node.remove();

                    paging.unmap(.{
                        .virt = addr,
                        .size = page_size,
                        .reclaim_pages = true,
                    }) catch unreachable;
                }

                self.bs.unset(buddy_index);
            }
        }
    };
}
