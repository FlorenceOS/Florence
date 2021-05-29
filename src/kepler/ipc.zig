const os = @import("root").os;
const std = @import("std");
const builtin = std.builtin;
const atmcqueue = os.lib.atmcqueue;
const thread = os.thread;
const kepler = os.kepler;

/// Note is the object that represents a notification.
/// They are allocated in place in other types, such as
/// .Stream or .Endpoint
pub const Note = struct {
    /// Type of the notification
    pub const Type = enum {
        /// Sent to server's notification queue when a new request
        /// to create a new stream on the owned endpoint was issued.
        /// Once recieved, a stream object is mapped to the object
        /// space of the server thread in a pending state
        RequestPending,
        /// Sent to client's notification queue when its request
        /// to make a stream was accepted. Once recieved, kernel
        /// performs the work needed for it to be used to exchange
        /// further notifications
        RequestAccepted,
        /// Sent to client's notification queue when its request
        /// to make a stream was denied. Once recieved, kernel
        /// transfers consumer to the .Denied state, in which
        /// the only valid call on the stream would be close()
        RequestDenied,
        /// Sent to server's notification queue with the intent
        /// to notify the server that more tasks are available
        /// for it to handle.
        TasksAvailable,
        /// Sent to client's notification queue with the intent
        /// to notify the client that some of the task were
        /// completed and their results are available to the client
        ResultsAvailable,
        /// Sent to the server's notification queue when client leaves
        /// to notify the server that client has abandoned the stream
        ConsumerLeft,
        /// Sent to the client's notification queue when server leaves
        /// to notify the client that server has abandoned the stream
        ProducerLeft,
        /// Sent to the server's notification queue to indicate that
        /// all references to the endpoint are lost. The purpose is to allow server
        /// to cleanup all the structures that were used for the endpoint
        EndpointUnreachable,
        /// Sent to the server's notification queue to indicate that
        /// all references to the locked handle are lost. The purpose is to allow server
        /// to cleanup all the structures that were associated with locked handle
        LockedHandleUnreachable,
        /// Sent to the driver whenever owned InterruptObject
        /// raises interrupt
        InterruptRaised,
        /// Get peer type from the note type (whether this note is directed
        /// to producer or consumer)
        pub fn to_peer_type(self: @This()) Stream.Peer {
            return switch (self) {
                .RequestPending, .TasksAvailable, .ConsumerLeft => .Producer,
                .RequestAccepted, .RequestDenied, .ResultsAvailable, .ProducerLeft => .Consumer,
                .InterruptRaised, .EndpointUnreachable, .LockedHandleUnreachable => {
                    @panic("to_peer_type called on a wrong message type");
                },
            };
        }
    };

    /// Hook for the atomic queue in NoteQueue
    hook: atmcqueue.Node = undefined,
    /// Type of the notification
    typ: Type,
    /// Borrowed reference to the owner
    owner_ref: union {
        /// For all the note types except listed below, this
        /// field stores reference to the stream object over which message was sent
        stream: *Stream,
        /// For the .EndpointUnreachable, this field stores the reference to the endpoint,
        /// all references to which are lost
        endpoint: *Endpoint,
        /// For the .LockedHandleUnreachable, this field stores the reference to the locked handle
        /// all references to which are lost
        locked_handle: *kepler.objects.LockedHandle,
        /// For the .interruptRaised, this field stores the reference to the InterruptObject
        /// that has raised the interrupt
        interrupt: *kepler.interrupts.InterruptObject,
    },

    /// Drop reference from the note.
    pub fn drop(self: *@This()) void {
        switch (self.typ) {
            .EndpointUnreachable => self.owner_ref.endpoint.drop(),
            .InterruptRaised => self.owner_ref.interrupt.drop(),
            .LockedHandleUnreachable => self.owner_ref.locked_handle.drop(),
            else => self.owner_ref.stream.drop(),
        }
    }

    /// Determine if note is up to date, meaning that this
    /// notification would have any worth to queue owner.
    /// The meaning of that depends on the note typpe
    fn is_active(self: *@This()) bool {
        switch (self.typ) {
            // For .RequestPending type, we need to check
            // that endpoint client tries to connect to
            // is still up
            .RequestPending => {
                if (!self.owner_ref.stream.endpoint.is_active()) {
                    return false;
                }
            },
            // For .EndpointUnreachable, we need to check that
            // endpoint is still up
            .EndpointUnreachable => {
                if (!self.owner_ref.endpoint.is_active()) {
                    return false;
                }
            },
            // We are always interested in locked handle notifications since we want to dispose
            // resources
            .LockedHandleUnreachable => {},
            // For .RequestDenied and .RequestAccepted types, we need to check that
            // we still have pending stream object unclosed
            .RequestDenied, .RequestAccepted => {
                if (!self.owner_ref.stream.assert_status(.Consumer, .Pending)) {
                    return false;
                }
            },
            // For .TasksAvailable/.ResultsAvailable/.ConsumerLeft/.ProducerLeft
            // just check that we are still connected to the stream
            .TasksAvailable, .ResultsAvailable, .ConsumerLeft, .ProducerLeft => {
                const peer = self.typ.to_peer_type();
                if (!self.owner_ref.stream.assert_status(peer, .Connected)) {
                    return false;
                }
            },
            // For .InterruptRaised, check if new interrupts are still being
            // waited for
            .InterruptRaised => {
                if (!self.owner_ref.interrupt.is_active()) {
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
    queue: atmcqueue.MPSCUnboundedQueue(Note, "hook"),
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
        instance.queue.init();
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
    pub fn try_recv(self: *@This()) ?*Note {
        retry: while (self.event.try_ack()) {
            // Poll until we get the message
            while (true) {
                const note = self.queue.dequeue() orelse continue;
                // Dispose note if its useless
                if (!note.is_active()) {
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
    /// Note that will be sent to the owner's notification queue
    /// when all references to the endpoint are lost
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
    fn send_request(self: *@This(), note: *Note) !void {
        if (!self.is_active()) {
            return error.EndpointUnreachable;
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
        // At this point, all non-owning references are lost
        // If death note was already sent, we can decrement owning count
        // as no more client references will be sent
        if (@atomicLoad(bool, &self.death_note_sent, .Acquire)) {
            self.decrement_internal();
            return;
        }
        // If it wasn't set, we don't want to decrement owning-refcount,
        // as note will still store client (non-ownning) references to the object
        @atomicStore(bool, &self.death_note_sent, true, .Release);
        // Check if server is already dead. If it die later,
        // server notification queue will clean everything up anyways
        if (@atomicLoad(bool, &self.dying, .Acquire)) {
            // If we can't send a reference, just terminate
            self.decrement_internal();
            return;
        }
        // Send ping of death note
        self.death_note.typ = .EndpointUnreachable;
        self.death_note.owner_ref = .{ .endpoint = self.borrow() };
        // If send failed, we can just ignore the failure
        // drop() called in send() will see that message was already sent
        // and will terminate
        self.queue.send(&self.death_note) catch {};
    }

    /// Drop owning reference to the endpoint
    pub fn shutdown(self: *@This()) void {
        // Indicate that we shut down the server
        @atomicStore(bool, &self.dying, true, .Release);
        // Decrement internal reference count
        self.decrement_internal();
    }

    /// Decrement internal owning reference count
    fn decrement_internal(self: *@This()) void {
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
    fn is_active(self: *const @This()) bool {
        return !@atomicLoad(bool, &self.dying, .Acquire);
    }
};

/// Stream is an object that allows two peers to exchange
/// notification with each other. Each stream has only two peers -
/// .Producer and .Consumer
pub const Stream = struct {
    /// Peer type
    pub const Peer = enum(u1) {
        /// Consumer is the peer that initially sent a request
        /// to make a stream
        Consumer = 0,
        /// Producer is the peer that accepted request to make
        /// a stream
        Producer = 1,

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
        Pending,
        /// (Producer-only) Producer has already sent a message
        ResponseSent,
        /// Peer is going to accept all incoming notifications
        Connected,
        /// Peer is no longer connected to the stream
        Abandoned,
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

    /// Notes that will be used to notify
    /// producer/consumer about more data to process
    notes: [2]Note,
    /// Notification queues of producer and consumer
    note_queues: [2]*NoteQueue,
    /// Set to true if a corresponding note can be resent
    ready_to_resend: [2]bool,
    /// Peers' connecivity status
    status: [2]PeerStatus,
    /// Notes that are used to notify about
    /// consumer/producer abandoning the stream
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
        const page_size = kepler.memory.get_smallest_page_size();
        // Producer RW buffer
        const producer_rw_object = try kepler.memory.MemoryObjectRef.create_plain(
            allocator,
            page_size,
            info.producer_rw_buf_size,
            kepler.memory.MemoryPerms.rw(),
        );
        errdefer producer_rw_object.drop();
        // Consumer RW buffer
        const consumer_rw_object = try kepler.memory.MemoryObjectRef.create_plain(
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
        instance.status = [2]PeerStatus{ .Pending, .Pending };
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
        instance.memory_objs[Peer.Producer.idx()] = producer_rw_object;
        instance.memory_objs[Peer.Consumer.idx()] = consumer_rw_object;
        // Prepare message
        instance.notes[Peer.Producer.idx()].typ = .RequestPending;
        instance.notes[Peer.Producer.idx()].owner_ref = .{ .stream = instance.borrow() };
        // No need to drop instance on errdefer, that will be collected anyway
        // Send request
        endpoint.send_request(&instance.notes[Peer.Producer.idx()]) catch |err| {
            return err;
        };
        return instance;
    }

    /// React to the join request by sending accept/request note
    fn react(self: *@This(), typ: Note.Type) !void {
        // Check that consumer and producer both have pending status
        if (!self.is_pending()) {
            // If we have sent a response already, return
            // .ResponseAlreadySent error
            if (self.assert_status(.Producer, .ResponseSent)) {
                return error.ResponseAlreadySent;
            }
            return error.ConnectionEstablished;
        }
        // Transition to .ResponseAlreadySent state
        @atomicStore(PeerStatus, &self.status[Peer.Producer.idx()], .ResponseSent, .Release);
        // Send message
        self.notes[Peer.Consumer.idx()].typ = typ;
        self.notes[Peer.Consumer.idx()].owner_ref = .{ .stream = self.borrow() };
        self.note_queues[Peer.Consumer.idx()].send(&self.notes[Peer.Consumer.idx()]) catch |err| {
            return err;
        };
    }

    /// Finalize accept/request sequence
    pub fn finalize_connection(self: *@This()) void {
        // Allow both threads to exchange messages
        @atomicStore(bool, &self.ready_to_resend[0], true, .Release);
        @atomicStore(bool, &self.ready_to_resend[1], true, .Release);
        // Set states
        @atomicStore(PeerStatus, &self.status[0], .Connected, .Release);
        @atomicStore(PeerStatus, &self.status[1], .Connected, .Release);
    }

    /// Allow peer to resend notification
    pub fn unblock(self: *@This(), peer: Peer) void {
        @atomicStore(bool, &self.ready_to_resend[peer.idx()], true, .Release);
    }

    /// Accept join request
    pub fn accept(self: *@This()) !void {
        try self.react(.RequestAccepted);
    }

    /// Notify other peer about this peer abandoning the stream
    fn notify_term(self: *@This(), peer: Peer) !void {
        const target = peer.other();
        // Other thread already left, no need to notify
        if (self.assert_status(target, .Abandoned)) {
            return;
        }
        const death_node = &self.death_notes[target.idx()];
        death_node.typ = if (peer == .Producer) .ProducerLeft else .ConsumerLeft;
        death_node.owner_ref = .{ .stream = self.borrow() };
        try self.note_queues[target.idx()].send(death_node);
    }

    /// Abandon connection from a given peer's side
    pub fn abandon(self: *@This(), peer: Peer) void {
        @atomicStore(PeerStatus, &self.status[peer.idx()], .Abandoned, .Release);
        if (self.is_pending()) {
            if (peer == .Producer) {
                self.react(.RequestDenied) catch {};
            }
        } else {
            if (!self.assert_status(peer.other(), .Abandoned)) {
                self.notify_term(peer) catch {};
            }
        }
        self.drop();
    }

    /// Notify producer or consumer about more tasks
    /// or more results being available
    pub fn notify(self: *@This(), peer: Peer) !void {
        if (!self.is_established()) {
            return error.ConnectionNotEstablished;
        }
        // If notificaton was already sent and not yet handled, just ignore
        if (!@atomicLoad(bool, &self.ready_to_resend[peer.idx()], .Acquire)) {
            return;
        }
        @atomicStore(bool, &self.ready_to_resend[peer.idx()], false, .Release);
        // Send notifiaction
        self.notes[peer.idx()].typ = if (peer == .Consumer) .ResultsAvailable else .TasksAvailable;
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
    fn assert_status(self: *const @This(), peer: Peer, status: PeerStatus) bool {
        return @atomicLoad(PeerStatus, &self.status[peer.idx()], .Acquire) == status;
    }

    /// Returns true if connection is established
    fn is_established(self: *const @This()) bool {
        return self.assert_status(.Consumer, .Connected) and self.assert_status(.Producer, .Connected);
    }

    /// Returns true if connection status on both sides is pending
    fn is_pending(self: *const @This()) bool {
        return self.assert_status(.Consumer, .Pending) and self.assert_status(.Producer, .Pending);
    }
};
