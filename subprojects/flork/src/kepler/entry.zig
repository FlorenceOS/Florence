usingnamespace @import("root").preamble;

/// User API entry allows threads to call kepler syscalls
pub const Entry = struct {
    /// Pointer to the universe
    universe: *os.kepler.objects.Universe,
    /// Allocator used for user API entry
    allocator: *std.mem.Allocator,

    /// Create new user API entry
    pub fn init(allocator: *std.mem.Allocator) !@This() {
        const universe = try os.kepler.objects.Universe.create(allocator);
        return @This(){
            .universe = universe,
            .allocator = allocator,
        };
    }

    /// Deinitialize user API entry
    pub fn deinit(self: *@This()) void {
        self.universe.drop();
    }

    /// Create new mailbox
    pub fn sysCreateMailbox(self: *@This(), slots: usize) !usize {
        const mailbox = try os.kepler.notifications.Mailbox.create(self.allocator, slots);
        self.universe.lock();
        const handle = try self.universe.putNolock(.{ .mailbox = mailbox });
        self.universe.unlock();
        return handle;
    }

    /// Create new caller
    pub fn sysCreateCaller(self: *@This(), hmailbox: usize, quota: usize, opaque_val: usize) !usize {
        self.universe.lock();
        defer self.universe.unlock();
        const mailbox = try self.universe.getMailboxAtNolock(hmailbox);
        const caller = try os.kepler.rpc.Caller.create(self.allocator, mailbox, quota, opaque_val);
        errdefer caller.shutdown();
        const result = try self.universe.putNolock(.{ .caller = caller });
        return result;
    }

    /// sysCreateCallee result
    pub const CalleeRefsPair = struct {
        owning_handle: usize,
        consumer_handle: usize,
    };

    /// Create new callee
    pub fn sysCreateCallee(self: *@This(), hmailbox: usize, hint: usize, opaque_val: usize) !CalleeRefsPair {
        self.universe.lock();
        defer self.universe.unlock();
        const mailbox = try self.universe.getMailboxAtNolock(hmailbox);
        const callee = try os.kepler.rpc.Callee.create(self.allocator, mailbox, hint, opaque_val);
        const howning = self.universe.putNolock(.{ .callee_owning = callee }) catch |err| {
            callee.drop();
            callee.drop();
            return err;
        };
        const hconsumer = self.universe.putNolock(.{ .callee_borrowed = callee }) catch |err| {
            callee.drop();
            self.universe.dropAtNolock(howning) catch unreachable;
            return err;
        };
        return CalleeRefsPair{ .owning_handle = howning, .consumer_handle = hconsumer };
    }

    /// Drop handle
    pub fn sysDropHandle(self: *@This(), handle: usize) !void {
        self.universe.lock();
        defer self.universe.unlock();
        try self.universe.dropAtNolock(handle);
    }

    /// Get notification
    pub fn sysGetNotification(
        self: *@This(),
        hmailbox: usize,
    ) !os.kepler.notifications.Notification {
        self.universe.lock();
        const mailbox = self.universe.borrowMailboxAtNolock(hmailbox) catch |err| {
            self.universe.unlock();
            return err;
        };
        defer mailbox.drop();
        self.universe.unlock();
        return mailbox.dequeue();
    }

    /// Initiate RPC
    pub fn sysDoRemoteCall(self: *@This(), hcaller: usize, hcallee: usize, msg: *const os.kepler.rpc.Message) !void {
        self.universe.lock();
        const callee = try self.universe.borrowBorrowedCalleeAtNolock(hcallee);
        defer callee.dropBorrowed();
        const caller = try self.universe.borrowCallerAtNolock(hcaller);
        defer caller.drop();
        self.universe.unlock();
        return caller.sendRPCRequest(callee, msg);
    }

    /// Get RPC reply
    pub fn sysGetRemoteCallReply(self: *@This(), hcaller: usize, msg: *os.kepler.rpc.Message) !void {
        self.universe.lock();
        const caller = try self.universe.borrowCallerAtNolock(hcaller);
        defer caller.drop();
        self.universe.unlock();
        return caller.getRPCResponse(msg);
    }

    /// Accept remote call
    pub fn sysAcceptRemoteCall(self: *@This(), hcallee: usize, msg: *os.kepler.rpc.Message) !void {
        self.universe.lock();
        const callee = try self.universe.borrowOwningCalleeAtNolock(hcallee);
        defer callee.drop();
        self.universe.unlock();
        return callee.acceptRPC(msg);
    }

    /// Return remote call
    pub fn sysReturnRemoteCall(self: *@This(), hcallee: usize, index: usize, msg: *const os.kepler.rpc.Message) !void {
        self.universe.lock();
        const callee = try self.universe.borrowOwningCalleeAtNolock(hcallee);
        defer callee.drop();
        self.universe.unlock();
        return callee.replyToRPC(index, msg);
    }
};
