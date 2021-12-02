const std = @import("std");
const rb = @import("rbtree");

const Order = std.math.Order;
const AddrNode = rb.Node(rb_features);
const SizeNode = rb.Node(rb_features);
const AddrTree = rb.Tree(Range, "addr_node", addr_config);
const SizeTree = rb.Tree(Range, "size_node", size_config);

const PlacementResult = struct {
    effective_size: u64,
    offset: u64,
};

const RangePlacement = struct {
    range: *Range,
    placement: PlacementResult,
};

const Range = struct {
    size_node: SizeNode = undefined,
    addr_node: AddrNode = undefined,
    base: usize,
    size: usize,

    fn getReturnedBase(self: *const @This(), alignment: usize) usize {
        if (alignment == 0)
            return self.base;
        return ((self.base + alignment - 1) / alignment) * alignment;
    }

    fn getEffectiveSize(size: usize, size_alignment: usize) usize {
        if (size_alignment == 0)
            return size;
        return ((size + size_alignment - 1) / size_alignment) * size_alignment;
    }

    pub fn tryPlace(
        self: *const @This(),
        size: usize,
        alignment: usize,
        size_alignment: usize,
    ) ?PlacementResult {
        const rbase = self.getReturnedBase(alignment);
        const es = getEffectiveSize(size, size_alignment);
        const offset = rbase - self.base;
        if (offset + es <= self.size) {
            return PlacementResult{
                .effective_size = es,
                .offset = offset,
            };
        }
        return null;
    }

    fn contains(self: *const @This(), addr: usize) bool {
        return addr >= self.base and addr < self.base + self.size;
    }
};

const AddressComparator = struct {
    pub fn compare(self: *const @This(), left: *const Range, right: *const Range) bool {
        _ = self;
        return left.base >= right.base;
    }
};

const SizeComparator = struct {
    pub fn compare(self: *const @This(), left: *const Range, right: *const Range) bool {
        _ = self;
        return left.size >= right.size;
    }
};

pub fn RangeAllocator(comptime LockType: type) type {
    return struct {
        ra: RangeAlloc,

        lock: LockType = .{},

        pub fn init(backing_allocator: std.mem.Allocator) @This() {
            return .{
                .ra = .{
                    .backing_allocator = backing_allocator,
                },
            };
        }

        pub fn allocator(self: *@This()) std.mem.Allocator {
            return std.mem.Allocator.init(self, alloc, resize, free);
        }

        pub fn alloc(
            self: *@This(),
            len: usize,
            ptr_align: u29,
            len_align: u29,
            ret_addr: usize,
        ) std.mem.Allocator.Error![]u8 {
            _ = ret_addr;
            self.lock.lock();
            defer self.lock.unlock();

            return self.ra.allocateAnywhere(len, ptr_align, len_align) catch |err| {
                switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => unreachable,
                }
            };
        }

        pub fn resize(
            self: *@This(),
            old_mem: []u8,
            old_align: u29,
            new_size: usize,
            len_align: u29,
            ret_addr: usize,
        ) ?usize {
            _ = self;
            _ = old_mem;
            _ = old_align;
            _ = new_size;
            _ = len_align;
            _ = ret_addr;
            // self.lock.lock();
            // defer self.lock.unlock();

            @panic("Todo: RangeAllocator.resize(): actually resize");
        }

        pub fn free(
            self: *@This(),
            old_mem: []u8,
            old_align: u29,
            ret_addr: usize,
        ) void {
            _ = ret_addr;
            _ = old_align;
            self.lock.lock();
            defer self.lock.unlock();

            // Free this address
            _ = self.ra.giveRange(.{
                .base = @ptrToInt(old_mem.ptr),
                .size = old_mem.len,
            }) catch |err| {
                switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => unreachable,
                }
            };
        }
    };
}

pub const RangeAlloc = struct {
    range_node_head: ?*Range = null,
    by_addr: AddrTree = AddrTree.init(.{}, {}),
    by_size: SizeTree = SizeTree.init(.{}, {}),

    backing_allocator: std.mem.Allocator,

    pub fn allocateAnywhere(
        self: *@This(),
        len: usize,
        ptr_align: usize,
        len_align: usize,
    ) !usize {
        const placement = try self.findPlacementAnywhere(len, ptr_align, len_align);

        const range = placement.range;
        const pmt = placement.placement;

        const ret = range.base;

        try self.maintainTree(range, pmt);

        return ret;
    }

    pub fn allocateAt(
        self: *@This(),
        addr: usize,
        len: usize,
    ) !void {
        const placement = try self.findPlacementAt(addr, len);

        const range = placement.range;
        const pmt = placement.placement;

        try self.maintainTree(range, pmt);
    }

    fn maintainTree(self: *@This(), range: *Range, pmt: PlacementResult) !void {
        // Node maintenance
        const has_data_before = pmt.offset != 0;
        const has_data_after = pmt.offset + pmt.effective_size < range.size;

        if (has_data_before and has_data_after) {
            // Add the new range
            const new_range_offset = pmt.offset + pmt.effective_size;
            _ = try self.addRange(.{
                .base = range.base + new_range_offset,
                .size = range.size - new_range_offset,
            });

            // Overwrite the old entry
            // Update size node (requires reinsertion)
            self.by_size.remove(range);
            range.size = pmt.offset;
            self.by_size.insert(range);
        } else if (has_data_after or has_data_before) {
            // Reuse the single node
            if (has_data_before) {
                // Cool, only the size has changed, no reinsertion on the addr node
                range.size = pmt.offset;
            } else {
                // Update addr node and reinsert
                self.by_addr.remove(range);
                range.size -= pmt.effective_size;
                range.base += pmt.effective_size;
                self.by_addr.insert(range);
            }

            // No matter what, we have to update the size node.
            self.by_size.remove(range);
            self.by_size.insert(range);
        } else {
            // Remove the node entirely
            self.by_addr.remove(range);
            self.by_size.remove(range);

            self.freeRange(range);
        }

        if (debug)
            self.dumpState();
    }

    fn locateAddressNode(self: *@This(), size_node: *Range) *Range {
        const node = self.by_addr.lookup(&size_node.node);
        if (node) |n| {
            return @fieldParentPtr(Range, "node", n);
        }
        unreachable;
    }

    fn findPlacementAnywhere(
        self: *@This(),
        size: usize,
        alignment: usize,
        size_alignment: usize,
    ) !RangePlacement {
        {
            const size_finder: struct {
                size: usize,

                pub fn check(finder: *const @This(), range: *const Range) bool {
                    return range.size >= finder.size;
                }
            } = .{ .size = size };

            var current_range = self.by_size.lowerBound(@TypeOf(size_finder), &size_finder);

            while (current_range) |range| {
                if (range.tryPlace(size, alignment, size_alignment)) |placement| {
                    return RangePlacement{
                        .range = range,
                        .placement = placement,
                    };
                }
                current_range = self.by_size.iterators.next(range);
            }
        }

        // We found nothing
        return error.OutOfMemory;
    }

    fn findPlacementAt(
        self: *@This(),
        addr: usize,
        size: usize,
    ) !RangePlacement {
        {
            const addr_finder: struct {
                addr: usize,

                pub fn check(finder: *const @This(), range: *const Range) bool {
                    return range.base + range.size >= finder.addr;
                }
            } = .{ .addr = addr };

            var range = self.by_addr.lowerBound(@TypeOf(addr_finder), &addr_finder);

            if (range) |r| {
                if (r.contains(addr) and r.contains(addr + size - 1)) {
                    return RangePlacement{
                        .range = r,
                        .placement = .{
                            .offset = addr - r.base,
                            .effective_size = size,
                        },
                    };
                }
            }
        }

        return error.OutOfMemory;
    }

    fn freeRange(self: *@This(), node: *Range) void {
        const new_head = @ptrCast(*?*Range, node);
        new_head.* = self.range_node_head;
        self.range_node_head = node;
    }

    fn consumeNodeBytes(self: *@This()) !void {
        const nodes = try self.backing_allocator.alloc(Range, 0x1000 / @sizeOf(Range));
        //const nodes = try os.memory.pmm.phys_heap.alloc(Range, 0x1000 / @sizeOf(Range));
        for (nodes) |*n| {
            self.freeRange(n);
        }
    }

    pub fn giveRange(self: *@This(), base: usize, size: usize) !void {
        const range = try self.addRange(.{
            .base = base,
            .size = size,
        });
        self.mergeRanges(range);
    }

    fn addRange(self: *@This(), in_range: Range) !*Range {
        const range = try self.allocRange();
        range.* = in_range;

        self.by_size.insert(range);
        self.by_addr.insert(range);
        return range;
    }

    fn allocRange(self: *@This()) !*Range {
        if (self.range_node_head == null) {
            try self.consumeNodeBytes();
        }
        if (self.range_node_head) |head| {
            const ret = head;
            self.range_node_head = @ptrCast(*?*Range, head).*;
            return ret;
        }
        unreachable;
    }

    // Needs to be a node in the addr tree
    fn mergeRanges(self: *@This(), range_in: *Range) void {
        var current = range_in;

        // Try to merge to the left
        while (self.by_addr.iterators.prev(current)) |prev| {
            if (self.tryMerge(prev, current)) {
                self.by_addr.remove(current);
                self.by_size.remove(current);
                self.freeRange(current);
                current = prev;
            } else {
                break;
            }
        }

        // Try to merge to the right
        while (self.by_addr.iterators.next(current)) |next| {
            if (self.tryMerge(current, next)) {
                self.by_addr.remove(next);
                self.by_size.remove(next);
                self.freeRange(next);
            } else {
                break;
            }
        }
    }

    fn tryMerge(self: *@This(), low: *Range, high: *const Range) bool {
        _ = self;
        if (low.base + low.size == high.base) {
            low.size += high.size;
            return true;
        }
        return false;
    }
};

const min_materialize_size = 64 * 1024;
const node_block_size = 0x1000 * @sizeOf(Range) / 16;

const debug = false;

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

const size_config: rb.Config = .{
    .features = rb_features,
    .augment_callback = null,
    .comparator = SizeComparator,
};
