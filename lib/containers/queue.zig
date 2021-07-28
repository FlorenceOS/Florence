usingnamespace @import("root").preamble;

/// Node hook for the queue. Embedded inside queue element.
pub const Node = struct {
    next: ?*Node = undefined,
};

/// Non-atomic queue
pub fn Queue(comptime T: type, comptime member_name: []const u8) type {
    return struct {
        head: ?*Node = null,
        tail: ?*Node = null,

        /// Convert reference to T to reference to atomic queue node
        fn refToNode(ref: *T) *Node {
            return &@field(ref, member_name);
        }

        /// Convert reference to atomic queue node to reference to T
        fn nodeToRef(node: *Node) *T {
            return @fieldParentPtr(T, member_name, node);
        }

        /// Enqueue node
        pub fn enqueue(self: *@This(), node: *T) void {
            const hook = refToNode(node);
            hook.next = null;

            if (self.tail) |tail_nonnull| {
                tail_nonnull.next = hook;
                self.tail = hook;
            } else {
                std.debug.assert(self.head == null);
                self.head = hook;
                self.tail = hook;
            }
        }

        // Dequeue node
        pub fn dequeue(self: *@This()) ?*T {
            if (self.head) |head_nonnull| {
                if (head_nonnull.next) |next| {
                    self.head = next;
                } else {
                    self.head = null;
                    self.tail = null;
                }
                return nodeToRef(head_nonnull);
            }
            return null;
        }

        // Get queue head element
        pub fn front(self: *@This()) ?*T {
            return if (self.head) |head| nodeToRef(head) else null;
        }
    };
}

test "insertion tests" {
    const TestNode = struct {
        hook: Node = undefined,
        val: u64,
    };
    var queue: Queue(TestNode, "hook") = .{};
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
