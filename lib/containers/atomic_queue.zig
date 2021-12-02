/// We are exporting Node from non-atomic queue module, since we want the same Node type to be used
/// both for atomic and non-atomic queues
pub const Node = @import("queue").Node;

const std = @import("std");

/// Multi producer single consumer unbounded atomic queue.
/// NOTE: Consumer is responsible for managing memory for nodes.
pub fn MPSCUnboundedQueue(comptime T: type, comptime member_name: []const u8) type {
    return struct {
        /// Head of the queue
        head: ?*Node = null,
        /// Tail of the queue
        tail: ?*Node = null,
        /// Dummy node
        dummy: Node = .{ .next = null },

        /// Convert reference to T to reference to atomic queue node
        fn refToNode(ref: *T) *Node {
            return &@field(ref, member_name);
        }

        /// Convert reference to atomic queue node to reference to T
        fn nodeToRef(node: *Node) *T {
            return @fieldParentPtr(T, member_name, node);
        }

        /// Enqueue element by reference to the node
        pub fn enqueueImpl(self: *@This(), node: *Node) void {
            node.next = null;
            const prev = @atomicRmw(?*Node, &self.head, .Xchg, node, .AcqRel) orelse &self.dummy;
            @atomicStore(?*Node, &prev.next, node, .Release);
        }

        /// Enqueue element
        pub fn enqueue(self: *@This(), elem: *T) void {
            self.enqueueImpl(refToNode(elem));
        }

        /// Try to dequeue
        pub fn dequeue(self: *@This()) ?*T {
            // Consumer thread will always have consistent view of tail, as its the one that reads
            // it / writes to it
            var tail: *Node = undefined;
            if (self.tail) |node| {
                tail = node;
            } else {
                tail = &self.dummy;
                self.tail = tail;
            }
            // Load next with acquire, as we don't want that to be reordered
            var next = @atomicLoad(?*Node, &tail.next, .Acquire);
            // Make sure that queue tail is not pointing at dummy element
            if (tail == &self.dummy) {
                if (next) |next_nonnull| {
                    // Skip dummy element. At this point, there is not a single pointer to dummy
                    self.tail = next_nonnull;
                    tail = next_nonnull;
                    next = @atomicLoad(?*Node, &tail.next, .Acquire);
                } else {
                    // No nodes in the queue =(
                    // (at least they were not visible to us)
                    return null;
                }
            }
            if (next) |next_nonnull| {
                // Tail exists (and not dummy), and next exists
                // Tail can be returned without worrying
                // about updates (they may only take place for the next node)
                self.tail = next_nonnull;
                return nodeToRef(tail);
            }
            // Tail exists, but next has not existed (it may now as code is lock free)
            // Check if head points to the same element as tail
            // (there is actually only one element)
            var head = @atomicLoad(?*Node, &self.head, .Acquire) orelse &self.dummy;
            // If tail != head, update is going on, as head was not linked with
            // next pointer
            // Condvar should pick up push event
            if (tail != head) {
                return null;
            }
            // Dummy node is not referenced by anything
            // and we have only one node left
            // Reinsert it as a marker for as to know
            // Where current queue ends
            self.enqueueImpl(&self.dummy);
            next = @atomicLoad(?*Node, &tail.next, .Acquire);
            if (next) |next_nonnull| {
                self.tail = next_nonnull;
                return nodeToRef(tail);
            }
            return null;
        }
    };
}

test "insertion tests" {
    const TestNode = struct {
        hook: Node = undefined,
        val: u64,
    };
    var queue: MPSCUnboundedQueue(TestNode, "hook") = .{};
    var elems = [_]TestNode{
        .{ .val = 1 },
        .{ .val = 2 },
        .{ .val = 3 },
    };
    queue.enqueue(&elems[0]);
    queue.enqueue(&elems[1]);
    queue.enqueue(&elems[2]);
    try std.testing.expect(queue.dequeue() == &elems[0]);
    try std.testing.expect(queue.dequeue() == &elems[1]);
    try std.testing.expect(queue.dequeue() == &elems[2]);
    try std.testing.expect(queue.dequeue() == null);
}
