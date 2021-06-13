usingnamespace @import("root").preamble;

const Order = std.math.Order;

const rb = lib.containers.rbtree;
const sbrk = os.memory.vmm.sbrk;
const Mutex = os.thread.Mutex;

const AddrNode = rb.Node(rb_features);
const SizeNode = rb.Node(rb_features);
const AddrTree = rb.Tree(Range, "addr_node", addr_config);
const SizeTree = rb.Tree(Range, "size_node", size_config);

const PlacementResult = struct {
    effective_size: u64,
    offset: u64,

    pub fn format(
        self: *const @This(),
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("size=0x{X}, offset=0x{X}", .{ self.effective_size, self.offset });
    }
};

const RangePlacement = struct {
    range: *Range,
    placement: PlacementResult,

    pub fn format(
        self: *const @This(),
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Placement{{{}, within freenode {}}}", .{ self.placement, self.range });
    }
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

    pub fn format(
        self: *const @This(),
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("[base: 0x{X} size: 0x{X}]", .{ self.base, self.size });
    }
};

const AddressComparator = struct {
    pub fn compare(self: *const @This(), left: *const Range, right: *const Range) bool {
        return left.base < right.base;
    }
};

const SizeComparator = struct {
    pub fn compare(self: *const @This(), left: *const Range, right: *const Range) bool {
        return left.size < right.size;
    }
};

pub const RangeAlloc = struct {
    range_node_head: ?*Range = null,
    allocator: std.mem.Allocator = .{
        .allocFn = alloc,
        .resizeFn = resize,
    },

    by_addr: AddrTree = AddrTree.init(.{}, {}),
    by_size: SizeTree = SizeTree.init(.{}, {}),

    mutex: Mutex = .{},

    backed: bool,

    fn dumpState(self: *@This()) void {
        if (!debug)
            return;

        os.log("Dumping range_alloc state\n", .{});

        var range = self.by_addr.iterators.first();
        while (range) |r| : (range = self.by_addr.iterators.next(r)) {
            os.log("{}\n", .{r});
        }
    }

    fn allocImpl(
        self: *@This(),
        len: usize,
        ptr_align: u29,
        len_align: u29,
        ret_addr: usize,
    ) ![]u8 {
        if (debug) {
            os.log("Calling alloc(len=0x{X},pa=0x{X},la=0x{X})\n", .{ len, ptr_align, len_align });
            self.dumpState();
        }

        const placement = try self.findPlacement(len, ptr_align, len_align);

        const range = placement.range;
        const pmt = placement.placement;

        // Return value
        const ret = @intToPtr([*]u8, range.base + pmt.offset)[0..len];

        // Node maintenance
        const has_data_before = pmt.offset != 0;
        const has_data_after = pmt.offset + pmt.effective_size < range.size;

        if (debug)
            os.log("Chose {}\n", .{placement});

        if (has_data_before and has_data_after) {
            if (debug)
                os.log("Has data before and after\n", .{});
            // Add the new range
            const new_range_offset = pmt.offset + pmt.effective_size;
            const new_range = self.addRange(.{
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
                if (debug)
                    os.log("Has data left before\n", .{});
                // Cool, only the size has changed, no reinsertion on the addr node
                range.size = pmt.offset;
            } else {
                if (debug)
                    os.log("Has data left after\n", .{});
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
            if (debug)
                os.log("Removing the node\n", .{});
            // Remove the node entirely
            self.by_addr.remove(range);
            self.by_size.remove(range);

            self.freeRange(range);
        }

        if (debug)
            self.dumpState();

        return ret;
    }

    fn alloc(
        allocator: *std.mem.Allocator,
        len: usize,
        ptr_align: u29,
        len_align: u29,
        ret_addr: usize,
    ) std.mem.Allocator.Error![]u8 {
        const self = @fieldParentPtr(@This(), "allocator", allocator);
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.allocImpl(len, ptr_align, len_align, ret_addr) catch |err| {
            switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    os.log("Alloc returned error: {}", .{err});
                    @panic("Alloc error");
                },
            }
        };
    }

    fn resize(
        allocator: *std.mem.Allocator,
        old_mem: []u8,
        old_align: u29,
        new_size: usize,
        len_align: u29,
        ret_addr: usize,
    ) std.mem.Allocator.Error!usize {
        const self = @fieldParentPtr(@This(), "allocator", allocator);
        self.mutex.lock();
        defer self.mutex.unlock();

        if (new_size != 0) {
            os.log("Todo: RangeAlloc.resize(): actually resize\n", .{});
            @panic("");
        }

        // Free this address
        const new_range = self.addRange(.{
            .base = @ptrToInt(old_mem.ptr),
            .size = old_mem.len,
        }) catch |err| {
            switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    os.log("Error while making new nodes for free(): {}\n", .{err});
                    @panic("");
                },
            }
        };

        // Attempt to merge nodes
        self.mergeRanges(new_range);

        return 0;
    }

    fn locateAddressNode(self: *@This(), size_node: *Range) *Range {
        const node = self.by_addr.lookup(&size_node.node);
        if (node) |n| {
            return @fieldParentPtr(Range, "node", n);
        }
        os.log("Could not locate addr node for {}\n", .{size_node});
        @panic("");
    }

    fn findPlacement(
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
                } else if (debug) {
                    os.log("Could not place into {}\n", .{range});
                }
                current_range = self.by_size.iterators.next(range);
            }
        }

        // We found nothing, make a new one
        if (debug) {
            os.log("Existing range not found, creating a new one\n", .{});
        }
        const range = try self.makeRange(size);
    
        if (range.tryPlace(size, alignment, size_alignment)) |placement| {
            return RangePlacement{
                .range = range,
                .placement = placement,
            };
        } else if (debug) {
            os.log("Could not place sz = 0x{X}, align = {}, szalign = {} in new allocation {}\n", .{
                size,
                alignment,
                size_alignment,
                range,
            },);
        }

        return error.OutOfMemory;
    }

    fn freeRange(self: *@This(), node: *Range) void {
        const new_head = @ptrCast(*?*Range, node);
        new_head.* = self.range_node_head;
        self.range_node_head = node;
    }

    fn consumeNodeBytes(self: *@This()) !void {
        const base = try sbrk(node_block_size);
        const nodes = @ptrCast([*]Range, @alignCast(@alignOf(Range), base));
        for (nodes[0 .. node_block_size / @sizeOf(Range)]) |*n| {
            self.freeRange(n);
        }
    }

    fn addRange(self: *@This(), in_range: Range) !*Range {
        const range = try self.allocRange();
        range.* = in_range;

        self.by_size.insert(range);
        self.by_addr.insert(range);
        return range;
    }

    fn makeRange(self: *@This(), minBytes: usize) !*Range {
        const page_size = os.platform.paging.page_sizes[0];
        const size = lib.util.libalign.alignUp(
            usize,
            page_size,
            std.math.max(min_materialize_size, minBytes),
        );
        const result: Range = .{
            .base = @ptrToInt(switch (self.backed) {
                true => (try os.memory.vmm.sbrk(size)).ptr,
                false => (try os.memory.vmm.sbrkNonbacked(size)).ptr,
            }),
            .size = size,
        };

        return self.addRange(result);
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
        @panic("No nodes!");
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
        if (low.base + low.size == high.base) {
            low.size += high.size;
            return true;
        }
        return false;
    }

    fn init(self: *@This()) void {
        self.mutex.init();
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
