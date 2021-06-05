usingnamespace @import("root").preamble;
const kepler = os.kepler;

/// Type of the object that can be stored in local object namespace
pub const ObjectType = enum {
    /// Object which exposes Stream interface. See Stream class description in kepler/ipc.zig.
    /// Not shareable.
    stream,
    /// Object which exposes Endpoint interface. See Stream class description in kepler/ipc.zig.
    /// Shareable.
    endpoint,
    /// Object which allows to access memory shared between arenas. See MemoryObject class
    /// description in kepler/memory.zig. Shareable
    memory_object,
    /// LockedHandle is the object that stores one integer only owner can access. See LockedHandle
    /// description in this file. Shareable
    locked_handle,
    /// InterruptObject is the object that owns interrupt source of any kind.
    interrupt_object,
    /// Used to indicate that this reference cell is empty
    none,
};

/// Type that represents local reference to the object
/// Unlike SharedObjectRef, it can represent references to not shareable objects such as streams.
/// It can store local metadata (e.g. address of the mapping for memory objects) as well
pub const ObjectRef = union(ObjectType) {
    /// Stream reference data
    stream: struct {
        /// Role of the reference owner in the connection
        peer: kepler.ipc.Stream.Peer,
        /// Reference to the stream object itself
        ref: *kepler.ipc.Stream,
    },
    /// Endpoint reference data
    endpoint: struct {
        /// Reference to the endpoint itself
        ref: *kepler.ipc.Endpoint,
        /// True if reference is owning reference
        is_owning: bool,
    },
    /// Memory object reference data
    memory_object: kepler.memory.MemoryObjectRef,
    /// Interrupt object
    interrupt_object: *kepler.interrupts.InterruptObject,
    /// Locked handle reference
    locked_handle: *LockedHandle,
    /// None means that there is no reference to any object
    none: void,

    /// Drop reference. mapper is the Mapper used by the arena (for .MemoryObject objects)
    pub fn drop(self: *const @This()) void {
        switch (self.*) {
            .stream => |stream| stream.ref.abandon(stream.peer),
            .endpoint => |endpoint| {
                if (endpoint.is_owning) {
                    endpoint.ref.shutdown();
                } else {
                    endpoint.ref.drop();
                }
            },
            .memory_object => |memory_object_ref| memory_object_ref.drop(),
            .locked_handle => |locked_handle| locked_handle.drop(),
            .interrupt_object => |interrupt_object| interrupt_object.shutdown(),
            .none => {},
        }
    }

    /// Drop and swap with null
    pub fn dropAndNullify(self: *@This()) void {
        self.drop();
        self.* = @This().None;
    }

    /// Borrow shareable reference. Increments refcount
    pub fn packShareable(self: *const @This()) !SharedObjectRef {
        switch (self.*) {
            .stream, .interrupt_object => return error.ObjectNotShareable,
            .endpoint => |endpoint| return SharedObjectRef{ .endpoint = endpoint.ref.borrow() },
            .memory_object => |memory_obj_ref| {
                return SharedObjectRef{ .memory_object = memory_obj_ref.borrow() };
            },
            .locked_handle => |locked_handle| {
                return SharedObjectRef{ .locked_handle = locked_handle.borrow() };
            },
            .none => return SharedObjectRef.none,
        }
    }

    /// Unpack from shareable. Consumes ref, hence does not increment reference count
    pub fn unpackShareable(ref: SharedObjectRef) @This() {
        switch (ref) {
            .endpoint => |endpoint| {
                return @This(){ .endpoint = .{ .ref = endpoint, .is_owning = false } };
            },
            .memory_object => |memory_obj_ref| return @This(){ .memory_object = memory_obj_ref },
            .locked_handle => |locked_handle| return @This(){ .locked_handle = locked_handle },
            .none => return @This().none,
        }
    }
};

/// Type of the object that can be passed with IPC
pub const SharedObjectType = enum {
    /// Shareable endpoint reference
    endpoint,
    /// Shareable memory object reference
    memory_object,
    /// Shareable locked handle reference
    locked_handle,
    /// Used to indicate that this reference cell is empty
    none,
};

/// Shareable reference to the object. Smaller than ObjectRef as it doesn't store any local
/// metadata. Can't store references to non-shareable objects such as streams as well. Used in IPC
pub const SharedObjectRef = union(SharedObjectType) {
    /// Shareable reference to the endpoint
    endpoint: *kepler.ipc.Endpoint,
    /// Shareable reference to the memory objects
    memory_object: kepler.memory.MemoryObjectRef,
    /// Shareable reference to the locked handle
    locked_handle: *LockedHandle,
    /// Idk, just none :^)
    none: void,

    /// Drop reference
    pub fn drop(self: *const @This()) void {
        switch (self.*) {
            .endpoint => |endpoint| endpoint.drop(),
            .locked_handle => |locked_handle| locked_handle.drop(),
            .memory_object => |memory_obj_ref| memory_obj_ref.drop(),
            .none => {},
        }
    }
};

/// Object that is used to pass references to other objects between threads
pub const ObjectRefMailbox = struct {
    /// Permissions for a given reference cell
    const Permissions = enum(u8) {
        /// Default state. Consumer is allowed to read or write
        /// to cell and immediately grant rights to the producer after that.
        /// Producer is not allowed to do anything.
        owned_by_consumer,
        /// Consumer has granted rights to read from cell. Now it can't do anything
        /// Producer is allowed to do one read and give rights back (aka burn after read)
        granted_read_rights,
        /// Consumer has granted rights ro write to cell. Now it can't do anything
        /// Producer is allowed to do one write and give rights back (aka burn after write)
        granted_write_rights,
        /// Consumer can read value from this location and transfer to owned_by_consumer state
        /// Producer has no rights
        to_read_by_consumer,
    };

    /// Cell is a combination of permissions and references
    const Cell = struct {
        perms: Permissions,
        ref: SharedObjectRef,
    };

    /// Array of cells
    cells: []Cell,
    /// Allocator used to allocate this object
    allocator: *std.mem.Allocator,

    /// Create mailbox
    pub fn init(allocator: *std.mem.Allocator, num: usize) !@This() {
        var result: @This() = undefined;
        result.cells = try allocator.alloc(Cell, num);
        for (result.cells) |*ref| {
            // Initially consumer owns every cell, as it is the one that
            // initiates requests
            ref.* = Cell{ .perms = .owned_by_consumer, .ref = SharedObjectRef.none };
        }
        result.allocator = allocator;
        return result;
    }

    /// Dispose internal structures
    pub fn drop(self: *const @This()) void {
        for (self.cells) |ref| {
            ref.ref.drop();
        }
        self.allocator.free(self.cells);
    }

    /// Checks that
    /// 1) Index is in bounds
    /// 2) Permission for the cell are equal to perms
    /// 3) If perms == .owned_by_consumer, asserts that cell points to null in debug mode
    fn checkBoundsAndStatus(self: *@This(), index: usize, perms: Permissions) !void {
        if (index > self.cells.len) {
            return error.OutOfBounds;
        }
        // Assert permission
        if (@atomicLoad(Permissions, &self.cells[index].perms, .Acquire) != perms) {
            return error.NotEnoughPermissions;
        }
        // Cells consumer has access to should always be nulled
        const is_nulled = std.meta.activeTag(self.cells[index].ref) == .none;
        std.debug.assert(perms != .owned_by_consumer or is_nulled);
    }

    /// Grant write rights. Invoked from consumer only
    pub fn grantWritePerms(self: *@This(), index: usize) !void {
        try self.checkBoundsAndStatus(index, .owned_by_consumer);
        @atomicStore(Permissions, &self.cells[index].perms, .granted_write_rights, .Release);
    }

    /// Assert permissions, read reference, modify permissions for a given cell
    fn read(
        self: *@This(),
        index: usize,
        old_perms: Permissions,
        new_perms: Permissions,
    ) !ObjectRef {
        // Assert perms
        try self.checkBoundsAndStatus(index, old_perms);
        // Move reference and set reference at this cell to None
        const result = ObjectRef.unpackShareable(self.cells[index].ref);
        self.cells[index].ref = SharedObjectRef.none;
        // Modify perms
        @atomicStore(Permissions, &self.cells[index].perms, new_perms, .Release);
        return result;
    }

    /// Read reference from the consumer side at a given index
    pub fn readFromConsumer(self: *@This(), index: usize) !ObjectRef {
        return self.read(index, .to_read_by_consumer, .owned_by_consumer);
    }

    /// Read reference from the producer side at a given index
    pub fn readFromProducer(self: *@This(), index: usize) !ObjectRef {
        return self.read(index, .granted_read_rights, .owned_by_consumer);
    }

    /// Write reference from consumer side
    pub fn writeFromConsumer(self: *@This(), index: usize, object: ObjectRef) !void {
        try self.checkBoundsAndStatus(index, .owned_by_consumer);
        self.cells[index].ref = try object.packShareable();
        @atomicStore(Permissions, &self.cells[index].perms, .granted_read_rights, .Release);
    }

    /// Write reference from producer side
    pub fn writeFromProducer(self: *@This(), index: usize, object: ObjectRef) !void {
        try self.checkBoundsAndStatus(index, .granted_write_rights);
        self.cells[index].ref = try object.packShareable();
        @atomicStore(Permissions, &self.cells[index].perms, .to_read_by_consumer, .Release);
    }
};

/// Locked handle object is the object that is capable of storing a single usize
/// integer in a way that only allows threads from owning arena to get the
/// integer value, while the object can be passed around freely
pub const LockedHandle = struct {
    /// Reference count
    ref_count: usize,
    /// Locked integer value
    handle: usize,
    /// Password. TODO: Set to arena ID or something
    password: usize,
    /// Allocator used to allocate the object
    allocator: *std.mem.Allocator,
    /// Death notification note
    death_note: kepler.ipc.Note,
    /// Pointer to the notification queue
    queue: *kepler.ipc.NoteQueue,
    /// True if death note was sent
    death_note_sent: bool,

    pub fn create(
        allocator: *std.mem.Allocator,
        handle: usize,
        password: usize,
        queue: *kepler.ipc.NoteQueue,
    ) !*LockedHandle {
        const instance = try allocator.create(@This());
        instance.ref_count = 1;
        instance.password = password;
        instance.handle = handle;
        instance.queue = queue.borrow();
        instance.death_note_sent = false;
        return instance;
    }

    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.ref_count, .Add, 1, .AcqRel);
        return self;
    }

    pub fn drop(self: *@This()) void {
        if (self.death_note_sent) {
            self.allocator.destroy(self);
        }
        if (@atomicRmw(usize, &self.ref_count, .Sub, 1, .AcqRel) > 1) {
            return;
        }
        self.death_note.typ = .locked_handle_unreachable;
        self.death_note.owner_ref = .{ .locked_handle = self.borrow() };
        // If send failed, we can just ignore the failure
        // drop() called in send() will see that message was already sent
        // and will terminate
        self.queue.send(&self.death_note) catch {};
    }

    pub fn peek(self: *const @This(), password: usize) !usize {
        if (self.password != password) {
            return error.AuthenticationFailed;
        }
        return self.handle;
    }
};
