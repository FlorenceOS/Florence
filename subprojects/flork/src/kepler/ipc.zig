usingnamespace @import("root").preamble;

/// IPC message
pub const Message = packed struct {
    /// Opaque value
    opaque_val: usize,
    /// Message data
    data: [56]u8,

    /// Encode reference to the token
    fn encodeTokenToOpaque(self: *@This(), token: *Token) void {
        self.opaque_val = @ptrToInt(token);
    }

    /// Decode token reference from opaque value
    fn decodeTokenFromOpaque(self: *@This()) *Token {
        return @intToPtr(*Token, self.opaque_val);
    }
};

/// IPC token. Process that gets its hands on the token can accept it and use it to send messages
/// Token also allows owner to set quota on the maximum number of messages that could be sent at once
pub const Token = struct {
    /// Reference count
    refcount: usize = 1,
    /// Reference to the owning mailbox
    owner: *Mailbox,
    /// True if token has been shut down
    is_shut_down: bool = false,
    /// Token lock
    lock: os.thread.Spinlock = .{},
    /// Number of messages that could be sent
    current_quota: usize,
    /// Token quota
    token_quota: usize,
    /// Token opaque value
    opaque_val: usize,
    /// Allocator used to allocate the token
    allocator: *std.mem.Allocator,

    /// Create token
    pub fn create(
        allocator: *std.mem.Allocator,
        owner: *Mailbox,
        quota: usize,
        opaque_val: usize,
    ) !*@This() {
        const result = try allocator.create(@This());
        errdefer allocator.destroy(result);

        const int_state = owner.lock.lock();
        defer owner.lock.unlock(int_state);

        if (owner.available_quota < quota) {
            return error.NotEnoughBuffers;
        }

        const borrowed = owner.borrow();
        owner.available_quota -= quota;

        result.* = .{
            .owner = borrowed,
            .current_quota = quota,
            .token_quota = quota,
            .opaque_val = opaque_val,
            .allocator = allocator,
        };

        return result;
    }

    /// Attempt to reserve one message slot
    fn reserve(self: *@This()) !void {
        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);

        if (self.is_shut_down) {
            return error.TokenExpired;
        }

        if (self.current_quota == 0) {
            return error.QuotaExceeded;
        }

        self.current_quota -= 1;
    }

    /// Free message slot
    fn freeSlot(self: *@This()) void {
        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);

        self.current_quota += 1;
    }

    /// Borrow reference to the token
    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.refcount, .Add, 1, .AcqRel);
        return self;
    }

    /// Drop reference to the toke
    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.refcount, .Sub, 1, .AcqRel) == 1) {
            self.dispose();
        }
    }

    /// Dispose token
    fn dispose(self: *@This()) void {
        self.owner.drop();
        self.allocator.destroy(self);
    }

    /// Shutdown token
    pub fn shutdown(self: *@This()) void {
        const int_state = self.lock.lock();
        self.is_shut_down = true;

        self.owner.lock.grab();
        self.owner.available_quota += self.token_quota;
        self.owner.lock.ungrab();

        self.lock.unlock(int_state);
        self.drop();
    }

    /// Send message to token
    pub fn send(self: *@This(), msg: *Message) !void {
        try self.reserve();

        const int_state = self.owner.lock.lock();
        defer self.owner.lock.unlock(int_state);

        if (self.owner.is_shut_down) {
            return error.MailboxUnreachable;
        }

        if (self.owner.sleep_queue.dequeue()) |sleep_node| {
            sleep_node.recv_buf.opaque_val = self.opaque_val;
            sleep_node.recv_buf.data = msg.data;
            os.thread.scheduler.wake(sleep_node.task);
        } else {
            const send_node = self.owner.free_queue.dequeue().?;
            const send_buf = self.owner.msgQueueNodeToBuffer(send_node);
            send_buf.encodeTokenToOpaque(self.borrow());
            send_buf.data = msg.data;
            self.owner.pending_queue.enqueue(send_node);
        }
    }
};

/// IPC mailbox. Allows to recieve IPC messages.
pub const Mailbox = struct {
    /// Message queue node
    const MsgQueueNode = struct {
        /// Queue node
        hook: lib.containers.queue.Node = .{},
    };

    /// Thread sleep queue node
    const TaskSleepQueueNode = struct {
        /// Queue node
        hook: lib.containers.queue.Node = .{},
        /// Pointer to the recieve buffer
        recv_buf: *Message,
        /// Pointer to the sleeping task
        task: *os.thread.Task,
    };

    /// Mailbox spinlock
    lock: os.thread.Spinlock = .{},
    /// Reference count
    refcount: usize = 1,
    /// Message buffers
    messages: []Message,
    /// Message queue nodes
    msg_queue_nodes: []MsgQueueNode,
    /// Free buffers queue
    free_queue: lib.containers.queue.Queue(MsgQueueNode, "hook") = .{},
    /// Pending messages queue
    pending_queue: lib.containers.queue.Queue(MsgQueueNode, "hook") = .{},
    /// Sleep queue
    sleep_queue: lib.containers.queue.Queue(TaskSleepQueueNode, "hook") = .{},
    /// Allocator used to allocate the token
    allocator: *std.mem.Allocator,
    /// True if mailbox was shut down
    is_shut_down: bool = false,
    /// Available quota for new token creation
    available_quota: usize,

    /// Create new mailbox
    pub fn create(allocator: *std.mem.Allocator, quota: usize) !*@This() {
        const result = try allocator.create(@This());
        errdefer allocator.destroy(result);

        const msg_bufs = try allocator.alloc(Message, quota);
        errdefer allocator.free(msg_bufs);

        const msg_nodes = try allocator.alloc(MsgQueueNode, quota);
        errdefer allocator.free(msg_nodes);

        result.* = .{
            .messages = msg_bufs,
            .msg_queue_nodes = msg_nodes,
            .allocator = allocator,
            .available_quota = quota,
        };

        for (msg_nodes) |*node| {
            result.free_queue.enqueue(node);
        }

        return result;
    }

    /// Borrow reference to the mailbox
    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.refcount, .Add, 1, .AcqRel);
        return self;
    }

    /// Drop reference to the mailbox
    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.refcount, .Sub, 1, .AcqRel) == 1) {
            self.dispose();
        }
    }

    /// Dispose mailbox
    fn dispose(self: *@This()) void {
        self.allocator.free(self.messages);
        self.allocator.free(self.msg_queue_nodes);
        self.allocator.destroy(self);
    }

    /// Shutdown mailbox
    pub fn shutdown(self: *@This()) void {
        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);

        self.is_shut_down = true;

        while (self.pending_queue.dequeue()) |incoming| {
            const msg_buf = self.msgQueueNodeToBuffer(incoming);
            const token = msg_buf.decodeTokenFromOpaque();
            token.drop();
        }
    }

    /// Convert message queue node pointer to message buffer pointer
    fn msgQueueNodeToBuffer(self: *const @This(), node: *MsgQueueNode) *Message {
        return &self.messages[lib.util.pointers.getIndex(node, self.msg_queue_nodes)];
    }

    /// Convert message buffer pointer to message queue node pointer
    fn bufferToMsgQueueNode(self: *const @This(), buf: *Message) *MsgQueueNode {
        return &self.msg_queue_nodes[lib.util.pointers.getIndex(buf, self.messages)];
    }

    /// Recieve message
    pub fn recieve(self: *@This(), buf: *Message) void {
        const int_state = self.lock.lock();

        if (self.pending_queue.dequeue()) |incoming| {
            const msg_buf = self.msgQueueNodeToBuffer(incoming);
            const token = msg_buf.decodeTokenFromOpaque();
            const opaque_val = token.opaque_val;

            buf.data = msg_buf.data;
            buf.opaque_val = opaque_val;
            self.free_queue.enqueue(incoming);
            self.lock.unlock(int_state);

            token.freeSlot();
            token.drop();
        } else {
            var sleep_node: TaskSleepQueueNode = .{
                .task = os.platform.get_current_task(),
                .recv_buf = buf,
            };
            self.sleep_queue.enqueue(&sleep_node);
            os.thread.scheduler.waitReleaseSpinlock(&self.lock);
            os.platform.set_interrupts(int_state);
        }
    }
};
