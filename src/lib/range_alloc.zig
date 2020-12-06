const std = @import("std");
const os = @import("root").os;

const Order = std.math.Order;

const rb    = os.external.rb;
const sbrk  = os.memory.vmm.sbrk;
const Mutex = os.thread.Mutex;

const max_alloc_size = 0x1000 << 10;
const node_block_size = 0x1000;

const PlacementResult = struct {
  effective_size: u64,
  offset: u64,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("size=0x{X}, offset=0x{X}", .{self.effective_size, self.offset});
  }
};

const Nodes = struct {
  size: *Range,
  addr: *Range,
};

const RangePlacement = struct {
  nodes: Nodes,
  placement: PlacementResult,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("Placement{{{}, within freenode {}}}", .{self.placement, self.nodes.size});
  }
};

const Range = struct {
  node: rb.Node = undefined,
  base: usize,
  size: usize,

  fn returned_base(self: *const @This(), alignment: usize) usize {
    if(alignment == 0)
      return self.base;
    return ((self.base + alignment - 1) / alignment) * alignment;
  }

  fn effective_size(size: usize, size_alignment: usize) usize {
    if(size_alignment == 0)
      return size;
    return ((size + size_alignment - 1) / size_alignment) * size_alignment;
  }

  pub fn try_place(self: *const @This(), size: usize, alignment: usize, size_alignment: usize) ?PlacementResult {
    const rbase = self.returned_base(alignment);
    const es = effective_size(size, size_alignment);
    const offset = rbase - self.base;
    if(offset + es < self.size) {
      return PlacementResult{
        .effective_size = es,
        .offset = offset,
      };
    }
    return null;
  }

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("[base: 0x{X} size: 0x{X}]", .{self.base, self.size});
  }
};

fn compare_addr(node_l: *rb.Node, node_r: *rb.Node, _: *rb.Tree) Order {
  const lhs = @fieldParentPtr(Range, "node", node_l);
  const rhs = @fieldParentPtr(Range, "node", node_r);

  return std.math.order(lhs.base, rhs.base);
}

fn compare_size(node_l: *rb.Node, node_r: *rb.Node, _: *rb.Tree) Order {
  const lhs = @fieldParentPtr(Range, "node", node_l);
  const rhs = @fieldParentPtr(Range, "node", node_r);

  const size_cmp = std.math.order(lhs.size, rhs.size);
  if(size_cmp != .eq)
    return size_cmp;

  return std.math.order(lhs.base, rhs.base);
}


pub const RangeAlloc = struct {
  range_node_head: ?*Range = null,
  allocator: std.mem.Allocator = .{
    .allocFn = alloc,
    .resizeFn = resize,
  },

  by_addr: rb.Tree = .{
    .root = null,
    .compareFn = compare_addr,
  },
  by_size: rb.Tree = .{
    .root = null,
    .compareFn = compare_size,
  },

  mutex: Mutex = .{},

  fn alloc_impl(self: *@This(), len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) ![]u8 {
    const placement = try self.find_placement(len, ptr_align, len_align);
    //os.log("Calling alloc(sz=0x{X}, align=0x{X}, len_align=0x{X})\n", .{len, ptr_align, len_align});
    //os.log("Got placement: {}\n", .{placement});

    const nodes = placement.nodes;
    const pmt = placement.placement;

    // Return value
    const ret = @intToPtr([*]u8, nodes.size.base + pmt.offset)[0..len];

    // Node maintenance
    const has_data_before = pmt.offset != 0;
    const has_data_after = pmt.offset + pmt.effective_size < nodes.size.size;

    if(has_data_before and has_data_after) {
      // Add the new range
      const new_nodes = self.add_range(.{
        .base = nodes.size.base + pmt.effective_size,
        .size = nodes.size.size - pmt.effective_size - pmt.offset,
      });
      errdefer self.by_addr.remove(&new_nodes.addr.node);
      errdefer self.free_node(new_nodes.addr);
      errdefer self.by_size.remove(&new_nodes.size.node);
      errdefer self.free_node(new_nodes.size);

      // Overwrite the old entry
      // Update size node (requires reinsertion)
      self.by_size.remove(&nodes.size.node);
      nodes.size.size = pmt.offset;
      if(self.by_size.insert(&nodes.size.node) != null) {
        os.log("Could not reinsert node after size update after split\n", .{});
        @panic("");
      }

      // Update address node (doesn't affect order; no reinsertion)
      nodes.addr.size = pmt.offset;
    }
    else if(has_data_after or has_data_before) {
      // Reuse the single node

      if(has_data_before) {
        // Cool, only the size has changed, no reinsertion on the addr node
        nodes.addr.size = pmt.offset;
      } else {
        // Update addr node and reinsert
        self.by_addr.remove(&nodes.addr.node);
        nodes.addr.size -= pmt.effective_size;
        nodes.addr.base += pmt.effective_size;
        if(self.by_addr.insert(&nodes.addr.node) != null) {
          os.log("Could not reinsert node after addr update after reuse\n", .{});
          @panic("");
        }
      }

      // No matter what, we have to update the size node.
      self.by_size.remove(&nodes.size.node);
      nodes.size.base = nodes.addr.base;
      nodes.size.size = nodes.addr.size;
      if(self.by_size.insert(&nodes.size.node) != null) {
        os.log("Could not reinsert node after size update after reuse\n", .{});
        @panic("");
      }
    }
    else {
      // Remove the node entirely
      self.by_addr.remove(&nodes.addr.node);
      errdefer self.by_addr.insert(&nodes.addr.node);
      self.free_node(nodes.addr);
      errdefer _ = alloc_node() catch unreachable;

      self.by_size.remove(&nodes.size.node);
      errdefer self.by_size.insert(&nodes.size.node);
      self.free_node(nodes.size);
      errdefer _ = alloc_node() catch unreachable;
    }

    return ret;
  }

  fn alloc(allocator: *std.mem.Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) std.mem.Allocator.Error![]u8 {
    const self = @fieldParentPtr(@This(), "allocator", allocator);
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.alloc_impl(len, ptr_align, len_align, ret_addr) catch |err| {
      switch(err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
          os.log("Alloc returned error: {}", .{err});
          @panic("Alloc error");
        }
      }
    };
  }

  fn resize(allocator: *std.mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, len_align: u29, ret_addr: usize) std.mem.Allocator.Error!usize {
    const self = @fieldParentPtr(@This(), "allocator", allocator);
    self.mutex.lock();
    defer self.mutex.unlock();

    if(new_size != 0) {
      os.log("Todo: RangeAlloc.resize(): actually resize\n", .{});
      @panic("");
    }

    // Free this address
    const new_nodes = self.add_range(.{
      .base = @ptrToInt(old_mem.ptr),
      .size = old_mem.len,
    }) catch |err| {
      switch(err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
          os.log("Error while making new nodes for free(): {}\n", .{err});
          @panic("");
        }
      }
    };

    // Attempt to merge nodes
    self.merge_addr_node(new_nodes.addr);

    return 0;
  }

  fn locate_addr_node(self: *@This(), size_node: *Range) *Range {
    const node = self.by_addr.lookup(&size_node.node);
    if(node) |n| {
      return @fieldParentPtr(Range, "node", n);
    }
    os.log("Could not locate addr node for {}\n", .{size_node});
    @panic("");
  }

  fn find_placement(self: *@This(), size: usize, alignment: usize, size_alignment: usize) !RangePlacement {
    // There is no rb.lower_bound or similar so we'll just iterate in linear time :(
    {
      var node = self.by_size.first();

      while(node) |n| {
        const range = @fieldParentPtr(Range, "node", n);
        if(range.try_place(size, alignment, size_alignment)) |placement| {
          return RangePlacement{
            .nodes = Nodes {
              .size = range,
              .addr = self.locate_addr_node(range),
            },
            .placement = placement,
          };
        }
        node = n.next();
      }
    }
    {
      // We found nothing, make a new one
      const nodes = try self.make_range();
      if(nodes.size.try_place(size, alignment, size_alignment)) |placement| {
        return RangePlacement{
          .nodes = nodes,
          .placement = placement,
        };
      }
    }

    os.log("Unable to find a size placement\n", .{});
    @panic("");
  }

  fn free_node(self: *@This(), node: *Range) void {
    const new_head = @ptrCast(*?*Range, node);
    new_head.* = self.range_node_head;
    self.range_node_head = node;
  }

  fn consume_node_bytes(self: *@This()) !void {
    const base = try sbrk(node_block_size);
    for(@ptrCast([*]Range, @alignCast(@alignOf(Range), base))[0..node_block_size/@sizeOf(Range)]) |*n|
      self.free_node(n);
  }

  fn add_range(self: *@This(), range: Range) !Nodes {
    const size_node = try self.alloc_node();
    errdefer self.free_node(size_node);

    const addr_node = try self.alloc_node();
    errdefer self.free_node(addr_node);

    addr_node.* = range;
    size_node.* = range;

    if(self.by_size.insert(&size_node.node) != null)
      @panic("by_size already exists!");
    errdefer self.by_size.remove(&size_node.node);

    if(self.by_addr.insert(&addr_node.node) != null)
      @panic("by_addr already exists!");
    errdefer self.by_addr.remove(&addr_node.node);

    return Nodes{
      .addr = addr_node,
      .size = size_node,
    };
  }

  fn make_range(self: *@This()) !Nodes {
    const result: Range = .{
      .base = @ptrToInt((try sbrk(max_alloc_size)).ptr),
      .size = max_alloc_size,
    };

    return self.add_range(result);
  }

  fn alloc_node(self: *@This()) !*Range {
    if(self.range_node_head == null) {
      try self.consume_node_bytes();
    }
    if(self.range_node_head) |head| {
      const ret = head;
      self.range_node_head = @ptrCast(*?*Range, head).*;
      return ret;
    }
    @panic("No nodes!");
  }

  // Needs to be a node in the addr tree
  fn merge_addr_node(self: *@This(), node_in: *Range) void {
    var node = node_in;
    {
      // Try to merge to the left
      while(true) {
        if(node.node.prev()) |prev_in| {
          const prev = @fieldParentPtr(Range, "node", prev_in);
          if(self.try_merge(prev, node)) {
            self.erase_size_node(node);
            self.by_addr.remove(&node.node);
            self.free_node(node);
            node = prev;
            continue;
          }
        }
        break;
      }
    }

    {
      // Try to merge to the right
      while(true) {
        if(node.node.next()) |next_in| {
          const next = @fieldParentPtr(Range, "node", next_in);
          if(self.try_merge(node, next)) {
            self.erase_size_node(next);
            self.by_addr.remove(&next.node);
            self.free_node(next);
            continue;
          }
        }
        break;
      }
    }
  }

  fn try_merge(self: *@This(), low: *Range, high: *const Range) bool {
    if(low.base + low.size == high.base) {
      low.size += high.size;
      return true;
    }
    return false;
  }

  fn erase_size_node(self: *@This(), node: *Range) void {
    const size_node = self.by_size.lookup(&node.node);
    if(size_node) |n| {
      self.by_size.remove(n);
      self.free_node(@fieldParentPtr(Range, "node", n));
      return;
    }
    @panic("Could not find node in size tree");
  }
};
