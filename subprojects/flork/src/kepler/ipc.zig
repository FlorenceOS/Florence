usingnamespace @import("root").preamble;

/// Messsage is the container for data sent via IPC
pub const Message = packed struct {
    /// Length of the data transferred within message (< payload.len)
    length: usize = 0,
    /// Payload transfered with the message
    payload: [128 - 1 * @sizeOf(usize)]u8 = undefined,

    /// Verify message
    pub fn valid(self: *const @This()) bool {
        return self.length <= 128 - 2 * @sizeOf(usize);
    }

    /// Copy from other message
    pub fn copyFrom(self: *@This(), other: *const @This()) void {
        std.mem.copy(u8, self.payload[0..other.length], other.payload[0..other.length]);
        self.length = other.length;
    }
};

/// Token represents a target of send operation
pub const Token = struct {
    /// Message buffers
    msgs: []Message,
    /// Message buffers circular queue head
    head: usize = 0,
    /// Message buffers circular queue tail
    tail: usize = 0,
    /// Token lock
    lock: os.thread.Spinlock = .{},
    /// Strong reference to the token's owner (mailbox)
    owner: *os.kepler.notifications.Mailbox,
    /// Reference count
    refcount: usize = 1,
    /// Allocator used to allocate the token
    allocator: *std.mem.Allocator,
    /// Opaque value associated with the token
    opaque_val: usize,
    /// True if notification for the token has been raised
    raised: bool = false,
    /// True if token has been shut down
    is_shut_down: bool = false,

    /// Create token
    pub fn create(
        allocator: *std.mem.Allocator,
        mailbox: *os.kepler.notifications.Mailbox,
        quota: usize,
        opaque_val: usize,
    ) !*@This() {
        const result = try allocator.create(@This());
        errdefer allocator.destroy(result);

        const msgs = try allocator.alloc(Message, quota);
        errdefer allocator.free(msgs);

        try mailbox.reserveSlot();

        result.* = .{
            .msgs = msgs,
            .owner = mailbox.borrow(),
            .allocator = allocator,
            .opaque_val = opaque_val,
        };

        return result;
    }

    /// Borrow reference to the token
    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.refcount, .Add, 1, .AcqRel);
        return self;
    }

    /// Drop reference to the token
    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.refcount, .Sub, 1, .AcqRel) == 1) {
            std.debug.assert(self.is_shut_down);
            self.owner.drop();
            self.allocator.free(self.msgs);
            self.allocator.destroy(self);
        }
    }

    /// Notify mailbox
    pub fn notify(self: *@This()) !void {
        if (!self.raised) {
            try self.owner.enqueue(.{
                .kind = .TokenUpdate,
                .opaque_val = self.opaque_val,
            });
            self.raised = true;
        }
    }

    /// Shutdown the token on producer side
    pub fn shutdownFromProducer(self: *@This()) void {
        const int_state = self.lock.lock();
        defer {
            self.lock.unlock(int_state);
            self.drop();
        }

        if (self.is_shut_down) {
            return;
        }
        self.is_shut_down = true;

        self.notify() catch {};
    }

    /// Shutdown the token on consumer side
    pub fn shutdownFromConsumer(self: *@This()) void {
        const int_state = self.lock.lock();
        defer {
            self.lock.unlock(int_state);
            self.drop();
        }

        self.owner.releaseSlot();
        self.is_shut_down = true;
    }

    /// Send message to the token
    pub fn send(self: *@This(), msg: *const Message) !void {
        if (!msg.valid()) {
            return error.InvalidMessage;
        }

        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);

        if (self.is_shut_down) {
            return error.DestinationUnreachable;
        }

        if (self.head - self.tail == self.msgs.len) {
            return error.QuotaExceeded;
        }

        const buf = &self.msgs[self.head % self.msgs.len];
        buf.copyFrom(msg);

        self.head += 1;
        try self.notify();
    }

    /// Recieve message. True if message has been recieved
    pub fn recieve(self: *@This(), buf: *Message) !bool {
        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);

        self.raised = false;

        if (self.is_shut_down) {
            return error.DestinationUnreachable;
        }

        if (self.head == self.tail) {
            return false;
        }

        const incoming = &self.msgs[self.tail % self.msgs.len];
        self.tail += 1;

        buf.copyFrom(incoming);
        return true;
    }
};
