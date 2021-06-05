usingnamespace @import("root").preamble;
const builtin = std.builtin;
const atomic_queue = lib.containers.atomic_queue;
const thread = os.thread;
const kepler = os.kepler;

/// Note is the object that represents a notification. They are allocated in place in other types,
/// such as .Stream or .Endpoint
pub const Note = struct {
    /// Type of the notification
    pub const Type = enum {
        /// Sent to server's notification queue when a new request to create a new stream on the
        /// owned endpoint was issued. Once recieved, a stream object is mapped to the object
        /// space of the server thread in a pending state
        request_pending,
        /// Sent to client's notification queue when its request to make a stream was accepted.
        /// Once recieved, kernel performs the work needed for it to be used to exchange further
        /// notifications
        request_accepted,
        /// Sent to client's notification queue when its request to make a stream was denied. Once
        /// recieved, kernel transfers consumer to the .Denied state, in which the only valid call
        /// on the stream would be close()
        request_denied,
        /// Sent to server's notification queue with the intent to notify the server that more tasks
        /// are available for it to handle.
        tasks_available,
        /// Sent to client's notification queue with the intent to notify the client that some of
        /// the task were completed and their results are available to the client
        results_available,
        /// Sent to the server's notification queue when client leaves to notify the server that
        /// client has abandoned the stream
        consumer_left,
        /// Sent to the client's notification queue when server leaves to notify the client that
        /// server has abandoned the stream
        producer_left,
        /// Sent to the server's notification queue to indicate that  all references to the endpoint
        /// are lost. The purpose is to allow server to cleanup all the structures that were used
        /// for the endpoint
        endpoint_unreachable,
        /// Sent to the server's notification queue to indicate that all references to the locked
        /// handle are lost. The purpose is to allow server to cleanup all the structures that were
        /// associated with locked handle
        locked_handle_unreachable,
        /// Sent to the driver whenever owned InterruptObject raises interrupt
        interrupt_raised,
        /// Get peer type from the note type (whether this note is directed to producer or consumer)
        pub fn toPeerType(self: @This()) Stream.Peer {
            return switch (self) {
                .request_pending, .tasks_available, .consumer_left => .producer,
                .request_accepted, .request_denied, .results_available, .producer_left => .consumer,
                .interrupt_raised, .endpoint_unreachable, .locked_handle_unreachable => {
                    @panic("toPeerType called on a wrong message type");
                },
            };
        }
    };

    /// Hook for the atomic queue in NoteQueue
    hook: atomic_queue.Node = undefined,
    /// Type of the notification
    typ: Type,
    /// Borrowed reference to the owner
    owner_ref: union {
        /// For all the note types except listed below, this field stores reference to the stream
        /// object over which message was sent
        stream: *Stream,
        /// For the .endpoint_unreachable, this field stores the reference to the endpoint, all
        /// references to which are lost
        endpoint: *Endpoint,
        /// For the .locked_handle_unreachable, this field stores the reference to the locked handle
        /// all references to which are lost
        locked_handle: *kepler.objects.LockedHandle,
        /// For the .interruptRaised, this field stores the reference to the InterruptObject that
        /// has raised the interrupt
        interrupt: *kepler.interrupts.InterruptObject,
    },

    /// Drop reference from the note.
    pub fn drop(self: *@This()) void {
        switch (self.typ) {
            .endpoint_unreachable => self.owner_ref.endpoint.drop(),
            .interrupt_raised => self.owner_ref.interrupt.drop(),
            .locked_handle_unreachable => self.owner_ref.locked_handle.drop(),
            else => self.owner_ref.stream.drop(),
        }
    }

    /// Determine if note is up to date, meaning that this notification would have any worth to
    /// queue owner. The meaning of that depends on the note typpe
    fn isActive(self: *@This()) bool {
        switch (self.typ) {
            // For .request_pending type, we need to check that endpoint client tries to connect to
            // is still up
            .request_pending => {
                if (!self.owner_ref.stream.endpoint.isActive()) {
                    return false;
                }
            },
            // For .endpoint_unreachable, we need to check that endpoint is still up
            .endpoint_unreachable => {
                if (!self.owner_ref.endpoint.isActive()) {
                    return false;
                }
            },
            // We are always interested in locked handle notifications since we want to dispose
            // resources
            .locked_handle_unreachable => {},
            // For .request_denied and .request_accepted types, we need to check that we still have
            // pending stream object unclosed
            .request_denied, .request_accepted => {
                if (!self.owner_ref.stream.assertStatus(.consumer, .pending)) {
                    return false;
                }
            },
            // For .tasks_available/.results_available/.consumer_left/.producer_left just check that we
            // are still connected to the stream
            .tasks_available, .results_available, .consumer_left, .producer_left => {
                const peer = self.typ.toPeerType();
                if (!self.owner_ref.stream.assertStatus(peer, .connected)) {
                    return false;
                }
            },
            // For .interrupt_raised, check if new interrupts are still being waited for
            .interrupt_raised => {
                if (!self.owner_ref.interrupt.isActive()) {
                    return false;
                }
            },
        }
        return true;
    }
};

/// NoteQueue is the object that represents a notification queue for a thread
pub const NoteQueue = struct {
    /// Notification queue state
    pub const State = enum(usize) {
        /// but it will handle all the ones sent
        Up, Down
    };

    /// Atomic queue that acts as a contatiner for the messages
    queue: atomic_queue.MPSCUnboundedQueue(Note, "hook"),
    /// Event object to listen for incoming messages
    event: thread.SingleListener,
    /// Refernce count
    ref_count: usize,
    /// State of the notification queue
    state: State,
    /// Allocator used to allocate the queue
    allocator: *std.mem.Allocator,

    /// Create notification stream object
    pub fn create(allocator: *std.mem.Allocator) !*@This() {
        const instance = try allocator.create(@This());
        instance.queue = .{};
        instance.ref_count = 1;
        instance.state = .Up;
        instance.allocator = allocator;
        instance.event = thread.SingleListener.init();
        return instance;
    }

    /// Borrow reference to the queue
    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.ref_count, .Add, 1, .AcqRel);
        return self;
    }

    /// Drop reference to the queue
    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.ref_count, .Sub, 1, .AcqRel) > 1) {
            return;
        }
        self.deinit();
    }

    /// Dispose queue
    fn deinit(self: *@This()) void {
        self.allocator.destroy(self);
    }

    /// Send note to the queue
    pub fn send(self: *@This(), note: *Note) !void {
        // Check queue state for the first time
        if (@atomicLoad(State, &self.state, .Acquire) != .Up) {
            return error.ThreadUnreachable;
        }
        // Notify queue owner about a new message
        if (!self.event.trigger()) {
            return error.ThreadUnreachable;
        }
        // Add note to the queue
        self.queue.enqueue(note);
    }

    /// Try to get a note from the queue
    pub fn tryRecv(self: *@This()) ?*Note {
        retry: while (self.event.try_ack()) {
            // Poll until we get the message
            while (true) {
                const note = self.queue.dequeue() orelse continue;
                // Dispose note if its useless
                if (!note.isActive()) {
                    note.drop();
                    break :retry;
                }
                return note;
            }
        }
        return null;
    }

    /// Wait for new notes
    pub fn wait(self: *@This()) void {
        self.event.wait();
    }

    /// Terminate the queue
    pub fn terminate(self: *@This()) void {
        // Prevent messages in the long run
        @atomicStore(State, &self.state, .Down, .Release);
        self.event.block();
        // Poll until we deallocate everything
        while (self.event.try_ack()) {
            const note = self.queue.dequeue() orelse continue;
            note.drop();
        }
        // Drop reference to this queue
        self.drop();
    }
};

/// Endpoint is the object that listens for new incoming connections
pub const Endpoint = struct {
    /// Note queue endpoint is attached to
    queue: *NoteQueue,
    /// Non-owning reference count
    non_own_ref_count: usize,
    /// Owning reference count
    /// +1 for connected server
    /// +1 if any client is connected
    own_ref_count: usize,
    /// Set to true if owner has dropped the endpoint
    dying: bool,
    /// Allocator used to allocate the endpoint
    allocator: *std.mem.Allocator,
    /// Note that will be sent to the owner's notification queue when all references to the endpoint
    /// are lost
    death_note: Note,
    /// Set to true if death note was already sent
    death_note_sent: bool,

    /// Create an endpoint
    pub fn create(allocator: *std.mem.Allocator, queue: *NoteQueue) !*@This() {
        const instance = try allocator.create(@This());
        instance.queue = queue.borrow();
        instance.non_own_ref_count = 0;
        instance.own_ref_count = 2;
        instance.death_note_sent = false;
        instance.dying = false;
        instance.allocator = allocator;
        return instance;
    }

    /// Send a join request
    fn sendRequest(self: *@This(), note: *Note) !void {
        if (!self.isActive()) {
            return error.endpoint_unreachable;
        }
        try self.queue.send(note);
    }

    /// Borrow non-owning reference to the endpoint
    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.non_own_ref_count, .Add, 1, .AcqRel);
        return self;
    }

    /// Drop non-owning reference to the endpoint
    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.non_own_ref_count, .Sub, 1, .AcqRel) > 1) {
            return;
        }
        // At this point, all non-owning references are lost. If death note was already sent, we can
        // decrement owning count as no more client references will be sent
        if (@atomicLoad(bool, &self.death_note_sent, .Acquire)) {
            self.decrementInternal();
            return;
        }
        // If it wasn't set, we don't want to decrement owning-refcount, as note will still store
        // client (non-ownning) references to the object
        @atomicStore(bool, &self.death_note_sent, true, .Release);
        // Check if server is already dead. If it die later, server notification queue will clean
        // everything up anyways
        if (@atomicLoad(bool, &self.dying, .Acquire)) {
            // If we can't send a reference, just terminate
            self.decrementInternal();
            return;
        }
        // Send ping of death note
        self.death_note.typ = .endpoint_unreachable;
        self.death_note.owner_ref = .{ .endpoint = self.borrow() };
        // If send failed, we can just ignore the failure drop() called in send() will see that
        // message was already sent and will terminate
        self.queue.send(&self.death_note) catch {};
    }

    /// Drop owning reference to the endpoint
    pub fn shutdown(self: *@This()) void {
        // Indicate that we shut down the server
        @atomicStore(bool, &self.dying, true, .Release);
        // Decrement internal reference count
        self.decrementInternal();
    }

    /// Decrement internal owning reference count
    fn decrementInternal(self: *@This()) void {
        if (@atomicRmw(usize, &self.own_ref_count, .Sub, 1, .AcqRel) > 1) {
            return;
        }
        self.deinit();
    }

    /// Dispose endpoint object
    fn deinit(self: *@This()) void {
        self.queue.drop();
        self.allocator.destroy(self);
    }

    /// Return true if endpoint still listens for incoming connections
    fn isActive(self: *const @This()) bool {
        return !@atomicLoad(bool, &self.dying, .Acquire);
    }
};

/// Stream is an object that allows two peers to exchange notification with each other. Each stream
/// has only two peers - .producer and .consumer
pub const Stream = struct {
    /// Peer type
    pub const Peer = enum(u1) {
        /// Consumer is the peer that initially sent a request to make a stream
        consumer = 0,
        /// Producer is the peer that accepted request to make a stream
        producer = 1,

        // Convert to index
        pub fn idx(self: Peer) u1 {
            return @enumToInt(self);
        }

        // Get enum member for other peer
        pub fn other(self: Peer) Peer {
            return @intToEnum(Peer, 1 - self.idx());
        }
    };

    /// Peer connection status
    /// https://github.com/ziglang/zig/issues/7976
    pub const PeerStatus = enum(usize) {
        /// Peer connection is still pending
        pending,
        /// (Producer-only) Producer has already sent a message
        response_sent,
        /// Peer is going to accept all incoming notifications
        connected,
        /// Peer is no longer connected to the stream
        abandoned,
    };

    /// Stream info exposed to userspace
    pub const UserspaceInfo = struct {
        /// Size of virtual memory for a consumer-rw producer-ro buffer
        consumer_rw_buf_size: usize,
        /// Size of virtual memory for a producer-rw consumer-ro buffer
        producer_rw_buf_size: usize,
        /// Size of object mailbox
        obj_mailbox_size: usize,
    };

    /// Notes that will be used to notify producer/consumer about more data to process
    notes: [2]Note,
    /// Notification queues of producer and consumer
    note_queues: [2]*NoteQueue,
    /// Set to true if a corresponding note can be resent
    ready_to_resend: [2]bool,
    /// Peers' connecivity status
    status: [2]PeerStatus,
    /// Notes that are used to notify about consumer/producer abandoning the stream
    death_notes: [2]Note,
    /// Reference count of the stream
    ref_count: usize,
    /// Allocator that was used to allocate the stream
    allocator: *std.mem.Allocator,
    /// Endpoint stream is attached to
    endpoint: *Endpoint,
    /// Memory objects for buffers
    memory_objs: [2]kepler.memory.MemoryObjectRef,
    /// Mailbox object for passing references
    mailbox: kepler.objects.ObjectRefMailbox,
    /// Info for userspace
    info: UserspaceInfo,

    /// Create stream object
    /// All stored resources are borrowed
    pub fn create(
        allocator: *std.mem.Allocator,
        consumer_queue: *NoteQueue,
        endpoint: *Endpoint,
        info: UserspaceInfo,
    ) !*@This() {
        // Allocate all structures as requested by the stream
        const page_size = kepler.memory.getSmallestPageSize();
        // Producer RW buffer
        const producer_rw_object = try kepler.memory.MemoryObjectRef.createPlain(
            allocator,
            page_size,
            info.producer_rw_buf_size,
            kepler.memory.MemoryPerms.rw(),
        );
        errdefer producer_rw_object.drop();
        // Consumer RW buffer
        const consumer_rw_object = try kepler.memory.MemoryObjectRef.createPlain(
            allocator,
            page_size,
            info.consumer_rw_buf_size,
            kepler.memory.MemoryPerms.rw(),
        );
        errdefer consumer_rw_object.drop();
        // Mailbox
        const mailbox = try kepler.objects.ObjectRefMailbox.init(allocator, info.obj_mailbox_size);
        errdefer mailbox.drop();
        // Create the instance and fill out fields
        const instance = try allocator.create(@This());
        errdefer allocator.destroy(instance);
        instance.ready_to_resend = [2]bool{ false, false };
        instance.ref_count = 1;
        instance.status = [2]PeerStatus{ .pending, .pending };
        instance.allocator = allocator;
        instance.info = info;
        // and queues
        instance.note_queues = [2]*NoteQueue{ consumer_queue.borrow(), endpoint.queue.borrow() };
        errdefer consumer_queue.drop();
        errdefer endpoint.queue.drop();
        // and endpoint
        instance.endpoint = endpoint.borrow();
        errdefer endpoint.drop();
        // and info
        instance.info = info;
        // and objects
        instance.mailbox = mailbox;
        instance.memory_objs[Peer.producer.idx()] = producer_rw_object;
        instance.memory_objs[Peer.consumer.idx()] = consumer_rw_object;
        // Prepare message
        instance.notes[Peer.producer.idx()].typ = .request_pending;
        instance.notes[Peer.producer.idx()].owner_ref = .{ .stream = instance.borrow() };
        // No need to drop instance on errdefer, that will be collected anyway
        // Send request
        endpoint.sendRequest(&instance.notes[Peer.producer.idx()]) catch |err| {
            return err;
        };
        return instance;
    }

    /// React to the join request by sending accept/request note
    fn react(self: *@This(), typ: Note.Type) !void {
        // Transition to .ResponseAlreadySent state
        @atomicStore(PeerStatus, &self.status[Peer.producer.idx()], .response_sent, .Release);
        // Send message
        self.notes[Peer.consumer.idx()].typ = typ;
        self.notes[Peer.consumer.idx()].owner_ref = .{ .stream = self.borrow() };
        self.note_queues[Peer.consumer.idx()].send(&self.notes[Peer.consumer.idx()]) catch |err| {
            return err;
        };
    }

    /// Finalize accept/request sequence
    pub fn finalizeConnection(self: *@This()) void {
        // Allow both threads to exchange messages
        @atomicStore(bool, &self.ready_to_resend[0], true, .Release);
        @atomicStore(bool, &self.ready_to_resend[1], true, .Release);
        // Set states
        @atomicStore(PeerStatus, &self.status[0], .connected, .Release);
        @atomicStore(PeerStatus, &self.status[1], .connected, .Release);
    }

    /// Allow peer to resend notification
    pub fn unblock(self: *@This(), peer: Peer) void {
        @atomicStore(bool, &self.ready_to_resend[peer.idx()], true, .Release);
    }

    /// Accept join request
    pub fn accept(self: *@This()) !void {
        if (!self.isPending()) {
            return error.NotPending;
        }
        try self.react(.request_accepted);
    }

    /// Notify other peer about this peer abandoning the stream
    fn notifyTermination(self: *@This(), peer: Peer) !void {
        const target = peer.other();
        // Other thread already left, no need to notify
        if (self.assertStatus(target, .abandoned)) {
            return;
        }
        const death_node = &self.death_notes[target.idx()];
        death_node.typ = if (peer == .producer) .producer_left else .consumer_left;
        death_node.owner_ref = .{ .stream = self.borrow() };
        try self.note_queues[target.idx()].send(death_node);
    }

    /// Abandon connection from a given peer's side
    pub fn abandon(self: *@This(), peer: Peer) void {
        const pending = self.isPending();
        @atomicStore(PeerStatus, &self.status[peer.idx()], .abandoned, .Release);
        if (pending) {
            if (peer == .producer) {
                self.react(.request_denied) catch {};
            }
        } else {
            if (!self.assertStatus(peer.other(), .abandoned)) {
                self.notifyTermination(peer) catch {};
            }
        }
        self.drop();
    }

    /// Notify producer or consumer about more tasks
    /// or more results being available
    pub fn notify(self: *@This(), peer: Peer) !void {
        if (!self.isEstablished()) {
            return error.ConnectionNotEstablished;
        }
        // If notificaton was already sent and not yet handled, just ignore
        if (!@atomicLoad(bool, &self.ready_to_resend[peer.idx()], .Acquire)) {
            return;
        }
        @atomicStore(bool, &self.ready_to_resend[peer.idx()], false, .Release);
        // Send notifiaction
        const typ: Note.Type = if (peer == .consumer) .results_available else .tasks_available;
        self.notes[peer.idx()].typ = typ;
        self.notes[peer.idx()].owner_ref = .{ .stream = self.borrow() };
        try self.note_queues[peer.idx()].send(&self.notes[peer.idx()]);
    }

    /// Borrow reference to the stream
    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.ref_count, .Add, 1, .AcqRel);
        return self;
    }

    /// Drop non-owning reference to the stream
    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.ref_count, .Sub, 1, .AcqRel) > 1) {
            return;
        }
        self.deinit();
    }

    /// Dispose queue object
    pub fn deinit(self: *@This()) void {
        self.note_queues[0].drop();
        self.note_queues[1].drop();
        self.endpoint.drop();
        self.memory_objs[0].drop();
        self.memory_objs[1].drop();
        self.mailbox.drop();
        self.allocator.destroy(self);
    }

    /// Returns true if status of a peer equals to the given one
    fn assertStatus(self: *const @This(), peer: Peer, status: PeerStatus) bool {
        return @atomicLoad(PeerStatus, &self.status[peer.idx()], .Acquire) == status;
    }

    /// Returns true if connection is established
    fn isEstablished(self: *const @This()) bool {
        return self.assertStatus(.consumer, .connected) and self.assertStatus(.producer, .connected);
    }

    /// Returns true if connection status on both sides is pending
    fn isPending(self: *const @This()) bool {
        return self.assertStatus(.consumer, .pending) and self.assertStatus(.producer, .pending);
    }
};
