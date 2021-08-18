usingnamespace @import("root").preamble;

/// Notification is sent to the mailbox to indicate that some event has occured
pub const Notification = packed struct {
    /// Notification type
    pub const Kind = enum(usize) {
        TokenUpdate = 0,
    };
    /// Notification type
    kind: Kind,
    /// Opaque value passed with the notification
    opaque_val: usize,
};

/// Mailbox allows threads to listen for new notifications
pub const Mailbox = struct {
    /// Wait queue node
    const WaitQueueNode = struct {
        /// Queue node
        node: lib.containers.queue.Node = undefined,
        /// Pointer to the task to wake up
        task: *os.thread.Task,
        /// Recieved notification
        notification: Notification = undefined,
        /// True if mailbox has been shutdown
        is_shut_down: bool = undefined,
    };

    /// Notification buffers
    notifications: []Notification,
    /// Mailbox lock
    lock: os.thread.Spinlock = .{},
    /// Sleep queue
    sleeping: lib.containers.queue.Queue(WaitQueueNode, "node") = .{},
    /// Notification circular queue head
    head: usize = 0,
    /// Notification circular queue tail
    tail: usize = 0,
    /// Reference count
    refcount: usize = 1,
    /// Remaining quota on attached events
    quota: usize,
    /// Allocator used to allocate the token
    allocator: *std.mem.Allocator,
    /// True if mailbox has been shut down
    is_shut_down: bool = false,

    /// Create a new mailbox
    pub fn create(allocator: *std.mem.Allocator, max_notes: usize) !*@This() {
        const result = try allocator.create(@This());
        errdefer allocator.destroy(result);

        const notifications = try allocator.alloc(Notification, max_notes);

        result.* = .{
            .notifications = notifications,
            .quota = max_notes,
            .allocator = allocator,
        };

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
            std.debug.assert(self.is_shut_down);
            self.allocator.free(self.notifications);
            self.allocator.destroy(self);
        }
    }

    /// Reserve one slot for new event
    pub fn reserveSlot(self: *@This()) !void {
        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);
        if (self.is_shut_down) {
            return error.MailboxShutdown;
        }
        if (self.quota == 0) {
            return error.QuotaExceeded;
        }
        self.quota -= 1;
    }

    /// Release one slot
    pub fn releaseSlot(self: *@This()) void {
        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);
        self.quota += 1;
        std.debug.assert(self.quota <= self.notifications.len);
    }

    /// Enqueue notification
    pub fn enqueue(self: *@This(), note: Notification) !void {
        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);
        if (self.is_shut_down) {
            return error.DestinationUnreachable;
        }
        if (self.sleeping.dequeue()) |sleep_node| {
            sleep_node.is_shut_down = false;
            sleep_node.notification = note;
            os.thread.scheduler.wake(sleep_node.task);
        } else {
            self.notifications[self.head % self.notifications.len] = note;
            self.head += 1;
        }
    }

    /// Dequeue notificaton
    pub fn dequeue(self: *@This()) !Notification {
        const int_state = self.lock.lock();

        if (self.is_shut_down) {
            self.lock.unlock(int_state);
            return error.MailboxShutdown;
        }

        if (self.head == self.tail) {
            var sleep_node = WaitQueueNode{ .task = os.platform.get_current_task() };
            self.sleeping.enqueue(&sleep_node);
            os.thread.scheduler.waitReleaseSpinlock(&self.lock);
            defer os.platform.set_interrupts(int_state);

            if (sleep_node.is_shut_down) {
                return error.MailboxShutdown;
            }

            return sleep_node.notification;
        } else {
            const result = self.notifications[self.tail % self.notifications.len];
            self.tail += 1;
            self.lock.unlock(int_state);
            return result;
        }
    }

    /// Shutdown mailbox and drop reference to it
    pub fn shutdown(self: *@This()) void {
        const int_state = self.lock.lock();
        std.debug.assert(!self.is_shut_down);

        self.is_shut_down = true;
        self.lock.unlock(int_state);

        while (self.sleeping.dequeue()) |sleep_node| {
            sleep_node.is_shut_down = true;
            os.thread.scheduler.wake(sleep_node.task);
        }

        self.drop();
    }
};
