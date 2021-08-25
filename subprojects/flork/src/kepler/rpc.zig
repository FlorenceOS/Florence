usingnamespace @import("root").preamble;

/// Message is the container for data sent via IPC
pub const Message = packed struct {
    /// Message status
    pub const Status = enum(usize) {
        Ok = 0,
        RPCNotHandled = 1,
    };
    /// Length of the data transferred within message (< payload.len)
    length: usize = 0,
    /// Message index (opaque field for the initiator)
    opaque_val: usize = 0,
    /// Message status
    status: Status = .Ok,
    /// Payload transfered with the message
    payload: [128 - 3 * @sizeOf(usize)]u8 = undefined,

    /// Verify length
    fn isValidLength(length: usize) bool {
        return length <= 128 - 3 * @sizeOf(usize);
    }

    /// Copy contents from other message with length known beforehand
    fn copyContentsFrom(self: *@This(), other: *const @This(), length: usize) void {
        std.mem.copy(u8, self.payload[0..length], other.payload[0..length]);
        self.length = length;
    }

    /// Copy message from kernel space buffer
    fn copyContentsFromKernel(self: *@This(), other: *const @This()) void {
        self.copyContentsFrom(other, other.length);
    }

    /// Copy message from userspace buffer
    fn copyContentsFromUserspace(self: *@This(), other: *const @This()) !void {
        const length = other.length;
        if (!Message.isValidLength(length)) {
            return error.InvalidMessage;
        }
        self.copyContentsFrom(other, length);
    }
};

/// RPCData struct contains data about pending, waiting for reply and replied RPC
/// NOTE: To get RPCData from RPCNode, use .data
const RPCData = struct {
    /// Pointer to the caller object that has initated RPC
    caller: *Caller,
    /// Index of the message
    index: usize,
    /// Message sequence number
    seq: usize,

    /// Get pointer to the message buffer in the caller
    fn getMsgBuffer(self: *const @This()) *Message {
        return &self.caller.messages[self.index];
    }

    /// Copy RPC request from client buffer
    fn copyRequestFromCallerBuffer(self: *@This(), msg: *const Message) !void {
        const buf = self.getMsgBuffer();
        try buf.copyContentsFromUserspace(msg);
        self.caller.opaque_vals[self.index] = msg.opaque_val;
        // buf.status remains uninitialized
    }

    /// Copy RPC request to server buffer
    fn copyRequestToCalleeBuffer(self: *@This(), msg: *Message) void {
        const buf = self.getMsgBuffer();
        msg.status = .Ok;
        msg.opaque_val = self.seq;
        msg.copyContentsFromKernel(buf);
    }

    /// Copy RPC reply from server buffer
    fn copyReplyFromCalleeBuffer(self: *@This(), msg: *const Message) !void {
        const buf = self.getMsgBuffer();
        try buf.copyContentsFromUserspace(msg);
        buf.status = .Ok;
        // buf.opaque_val remains uninitialized
    }

    /// Create RPC not handled reply
    fn makeRPCNotHandledMsg(self: *@This()) void {
        const buf = self.getMsgBuffer();
        buf.status = .RPCNotHandled;
        buf.length = 0;
        // buf.opaque_val remains uninitialized
    }

    /// Copy RPC reply to client buffer
    fn copyReplyToCallerBuffer(self: *@This(), msg: *Message) void {
        const buf = self.getMsgBuffer();
        msg.status = buf.status;
        msg.opaque_val = self.caller.opaque_vals[self.index];
        msg.copyContentsFromKernel(buf);
    }
};

/// Doubly-linked list of RPC nodes
const RPCNodeList = std.TailQueue(RPCData);

/// RPC doubly-linked list node
const RPCNode = RPCNodeList.Node;

/// Caller is an object responsible for initiating RPC calls
pub const Caller = struct {
    /// Reference count
    refcount: usize = 1,
    /// Allocator caller has been allocated on
    allocator: *std.mem.Allocator,
    /// Message buffers
    messages: []Message,
    /// Preallocated RPC nodes
    rpc_nodes: []RPCNode,
    /// Hidden opaque values
    opaque_vals: []usize,
    /// Free RPC nodes queue
    free_queue: RPCNodeList = .{},
    /// Recieved replies RPC nodes queue
    recieved_replies: RPCNodeList = .{},
    /// Caller lock
    lock: os.thread.Spinlock = .{},
    /// Notification raiser
    raiser: os.kepler.notifications.NotificationRaiser,
    /// True if caller has been shutdown
    is_shut_down: bool = false,

    /// Create caller object
    pub fn create(
        allocator: *std.mem.Allocator,
        mailbox: *os.kepler.notifications.Mailbox,
        quota: usize,
        opaque_val: usize,
    ) !*@This() {
        const result = try allocator.create(@This());
        errdefer allocator.destroy(result);

        const messages = try allocator.alloc(Message, quota);
        errdefer allocator.free(messages);

        const nodes = try allocator.alloc(RPCNode, quota);
        errdefer allocator.free(nodes);

        const opaque_vals = try allocator.alloc(usize, quota);
        errdefer allocator.free(opaque_vals);

        const raiser = try os.kepler.notifications.NotificationRaiser.init(mailbox, .{
            .kind = .RPCReply,
            .opaque_val = opaque_val,
        });

        result.* = .{
            .allocator = allocator,
            .messages = messages,
            .rpc_nodes = nodes,
            .opaque_vals = opaque_vals,
            .raiser = raiser,
        };

        for (result.rpc_nodes) |*node, i| {
            node.data.index = i;
            result.free_queue.prepend(node);
        }

        return result;
    }

    /// Drop reference to the caller
    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.refcount, .Sub, 1, .AcqRel) == 1) {
            self.raiser.deinit();
            self.allocator.free(self.messages);
            self.allocator.free(self.rpc_nodes);
            self.allocator.free(self.opaque_vals);
            self.allocator.destroy(self);
        }
    }

    /// Borrow reference to the caller 
    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.refcount, .Add, 1, .AcqRel);
        return self;
    }

    /// Shutdown caller
    pub fn shutdown(self: *@This()) void {
        const int_state = self.lock.lock();
        self.is_shut_down = true;
        self.lock.unlock(int_state);
        self.drop();
    }

    /// Initiate RPC
    pub fn sendRPCRequest(self: *@This(), callee: *Callee, msg: *const Message) !void {
        // 0. Lock self and check if caller was shutdown
        const int_state = self.lock.lock();
        if (self.is_shut_down) {
            self.lock.unlock(int_state);
            return error.Shutdown;
        }
        // 1. Get slot
        const slot = self.free_queue.pop() orelse {
            self.lock.unlock(int_state);
            return error.QuotaExceeded;
        };
        // 2. Initialize slot caller field by borrowing ref to self. This is done to ensure that
        // message buffer isnt deallocated until RPC is recieved and handled by the callee
        slot.data.caller = self.borrow();
        // 3. Copy message. Opaque val is saved inside copyRequestFromCallerBuffer function
        slot.data.copyRequestFromCallerBuffer(msg) catch |err| {
            self.free_queue.prepend(slot);
            self.lock.unlock(int_state);
            // Drop ref we borrowed earlier
            self.drop();
            return error.InvalidMessage;
        };
        // 4. Unlock self. To avoid spinlocks, there is a strict rule: either callee or caller is locked
        // If we don't drop the lock here, we will violate this rule, as callee is locked on step 6
        self.lock.unlock(int_state);
        // 5. Great! RPC is ready to be delievered. Enqueue in callee pending queue
        callee.enqueuePending(slot) catch |err| {
            // Lock again to enqueue free slot
            const int_state2 = self.lock.lock();
            self.free_queue.prepend(slot);
            self.lock.unlock(int_state2);
            // Drop ref we borrowed earlier
            self.drop();
        };
    }

    /// Insert reply to RPC in reply queue. Drops reference to the node
    fn enqueueReply(self: *@This(), node: *RPCNode) !void {
        std.debug.assert(node.data.caller == self);
        // 0. Lock self and check if caller was shutdown
        const int_state = self.lock.lock();
        defer {
            // Drop lock and drop reference to the caller
            self.lock.unlock(int_state);
            self.drop();
        }
        if (self.is_shut_down) {
            return error.DestinationUnreachable;
        }
        // 1. Enqueue node
        self.recieved_replies.prepend(node);
        // 2. Raise notification
        self.raiser.raise();
    }

    /// Get reply from RPC reply queue
    pub fn getRPCResponse(self: *@This(), msg: *Message) !void {
        // 0. Lock self and check if caller was shutdown
        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);
        if (self.is_shut_down) {
            return error.Shutdown;
        }
        // 1. Dequeue from queue
        const node = self.recieved_replies.pop() orelse return error.Empty;
        // 2. Ack notification
        self.raiser.ack();
        // 3. Copy data to message
        node.data.copyReplyToCallerBuffer(msg);
        // 4. Enqueue in free queue
        self.free_queue.prepend(node);
    }
};

/// Callee is an object responsible for accepting RPC calls and replying to them
pub const Callee = struct {
    /// Reference count
    refcount: usize = 2,
    /// Consumer reference count
    consumer_refcount: usize = 1,
    /// Allocator caller has been allocated on
    allocator: *std.mem.Allocator,
    /// Recieved msgs hashmap
    recieved: []RPCNodeList,
    /// Pending RPC requests queue
    pending_queue: RPCNodeList = .{},
    /// Callee lock
    lock: os.thread.Spinlock = .{},
    /// Last allocated sequence number
    seq: usize = 0,
    /// Notification raiser
    raiser: os.kepler.notifications.NotificationRaiser,
    /// Termination raiser
    term_raiser: os.kepler.notifications.NotificationRaiser,
    /// True if callee has recieved shutdown
    is_shut_down: bool = false,

    /// Create callee
    pub fn create(
        allocator: *std.mem.Allocator,
        mailbox: *os.kepler.notifications.Mailbox,
        hint: usize,
        opaque_val: usize,
    ) !*@This() {
        const result = try allocator.create(@This());
        errdefer allocator.destroy(result);

        var raiser = try os.kepler.notifications.NotificationRaiser.init(mailbox, .{
            .kind = .RPCIncoming,
            .opaque_val = opaque_val,
        });
        errdefer raiser.deinit();

        var term_raiser = try os.kepler.notifications.NotificationRaiser.init(mailbox, .{
            .kind = .CalleeLost,
            .opaque_val = opaque_val,
        });
        errdefer term_raiser.deinit();

        const recieved = try allocator.alloc(RPCNodeList, hint);
        for (recieved) |*list| {
            list.* = .{};
        }

        result.* = .{
            .allocator = allocator,
            .raiser = raiser,
            .term_raiser = term_raiser,
            .recieved = recieved,
        };
        return result;
    }

    /// Drop reference to the callee
    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.refcount, .Sub, 1, .AcqRel) == 1) {
            self.raiser.deinit();
            self.term_raiser.deinit();
            self.allocator.free(self.recieved);
            self.allocator.destroy(self);
        }
    }

    /// Borrow owning reference
    pub fn borrowOwning(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.refcount, .Add, 1, .AcqRel);
        return self;
    }

    /// Borrow reference to the callee from consumer
    pub fn borrowConsumer(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.consumer_refcount, .Add, 1, .AcqRel);
        return self;
    }

    /// Enqueue pending RPC
    fn enqueuePending(self: *@This(), rpc: *RPCNode) !void {
        // 0. Lock self and check for shutdown
        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);
        if (self.is_shut_down) {
            return error.DestinationUnreachable;
        }
        // 1. Insert RPC in pending queue
        self.pending_queue.prepend(rpc);
        // 2. Raise notification
        self.raiser.raise();
    }

    /// Dequeue pending RPC
    pub fn acceptRPC(self: *@This(), msg: *Message) !void {
        // 0. Lock self and check for shutdown
        const int_state = self.lock.lock();
        defer self.lock.unlock(int_state);
        if (self.is_shut_down) {
            return error.Shutdown;
        }
        // 1. Dequeue pending IPC request
        const pending = self.pending_queue.pop() orelse return error.Empty;
        // 2. Assign sequence number
        const seq_mod = self.seq % self.recieved.len;
        pending.data.seq = self.seq;
        self.seq += 1;
        // 3. Add to the hashmap
        self.insertRPCToMap(pending);
        // 4. Store recieved message to the msg
        pending.data.copyRequestToCalleeBuffer(msg);
        // 5. Ack raiser
        self.raiser.ack();
    }

    /// Insert reply-awaing RPC to callee hashmap
    fn insertRPCToMap(self: *@This(), rpc: *RPCNode) void {
        self.recieved[rpc.data.seq % self.recieved.len].prepend(rpc);
    }

    /// Search for reply-awating RPC by index
    fn searchForAwaitingReply(self: *const @This(), index: usize) ?*RPCNode {
        const mod = index % self.recieved.len;
        var current = self.recieved[mod].first;
        while (current) |current_nonnull| : (current = current_nonnull.next) {
            if (current_nonnull.data.seq == index) {
                return current_nonnull;
            }
        }
        return null;
    }

    /// Remove reply-awaiting RPC from callee hashmap
    fn removeRPCFromMap(self: *@This(), rpc: *RPCNode) void {
        const mod = rpc.data.seq % self.recieved.len;
        self.recieved[mod].remove(rpc);
    }

    /// Reply to the RPC
    pub fn replyToRPC(self: *@This(), index: usize, reply: *const Message) !void {
        // 0. Lock self and check for shutdown
        const int_state = self.lock.lock();
        if (self.is_shut_down) {
            self.lock.unlock(int_state);
            return error.Shutdown;
        }
        const node = self.searchForAwaitingReply(index) orelse {
            self.lock.unlock(int_state);
            return error.InvalidIndex;
        };
        // 1. Copy reply
        node.data.copyReplyFromCalleeBuffer(reply) catch |err| {
            self.lock.unlock(int_state);
            return err;
        };
        // 3.Remove node from callee hashmap
        self.removeRPCFromMap(node);
        // 4. Unlock self
        self.lock.unlock(int_state);
        // 5. Enqueue it in replies queue
        try node.data.caller.enqueueReply(node);
    }

    /// Drop reference from consumer
    pub fn dropBorrowed(self: *@This()) void {
        if (@atomicRmw(usize, &self.consumer_refcount, .Sub, 1, .AcqRel) == 1) {
            const int_state = self.lock.lock();
            if (!self.is_shut_down) {
                self.term_raiser.raise();
            }
            self.lock.unlock(int_state);
            self.drop();
        }
    }

    /// Drop reference from owner
    pub fn dropOwning(self: *@This()) void {
        const int_state = self.lock.lock();
        self.is_shut_down = true;
        self.lock.unlock(int_state);
        var i: usize = 0;
        while (i < self.recieved.len) : (i += 1) {
            const list = &self.recieved[i];
            while (list.pop()) |node| {
                node.data.makeRPCNotHandledMsg();
                node.data.caller.enqueueReply(node) catch {};
            }
        }
        self.drop();
    }
};
