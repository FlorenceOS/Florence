const std = @import("std");
const os = @import("root").os;
const kepler = os.kepler;

/// Type of the object that can be stored in local object namespace
pub const ObjectType = enum {
    /// Object which exposes Stream interface. See Stream class description
    /// in kepler/ipc.zig. Not shareable.
    Stream,
    /// Object which exposes Endpoint interface. See Stream class description
    /// in kepler/ipc.zig. Shareable.
    Endpoint,
    /// Object which allows to access memory shared between arenas.
    /// See MemoryObject class description in kepler/memory.zig. Shareable
    MemoryObject,
    /// LockedHandle is the object that stores one integer only
    /// owner can access. See LockedHandle description in this file. Shareable
    LockedHandle,
    /// InterruptObject is the object that owns interrupt source of any kind.
    InterruptObject,
    /// Used to indicate that this reference cell is empty
    None,
};

/// Type that represents local reference to the object
/// Unlike SharedObjectRef, it can represent references
/// to not shareable objects such as streams. It can store
/// local metadata (e.g. address of the mapping for memory objects)
/// as well
pub const ObjectRef = union(ObjectType) {
    /// Stream reference data
    Stream: struct {
        /// Role of the reference owner in the connection
        peer: kepler.ipc.Stream.Peer,
        /// Reference to the stream object itself
        ref: *kepler.ipc.Stream,
    },
    /// Endpoint reference data
    Endpoint: struct {
        /// Reference to the endpoint itself
        ref: *kepler.ipc.Endpoint,
        /// True if reference is owning reference
        is_owning: bool,
    },
    /// Memory object reference data
    MemoryObject: kepler.memory.MemoryObjectRef,
    /// Interrupt object
    InterruptObject: *kepler.interrupts.InterruptObject,
    /// Locked handle reference
    LockedHandle: *LockedHandle,
    /// None means that there is no reference to any object
    None: void,

    /// Drop reference. mapper is the Mapper used by the arena (for .MemoryObject objects)
    pub fn drop(self: *const @This()) void {
        switch (self.*) {
            .Stream => |stream| stream.ref.abandon(stream.peer),
            .Endpoint => |endpoint| {
                if (endpoint.is_owning) {
                    endpoint.ref.shutdown();
                } else {
                    endpoint.ref.drop();
                }
            },
            .MemoryObject => |memory_object_ref| memory_object_ref.drop(),
            .LockedHandle => |locked_handle| locked_handle.drop(),
            .InterruptObject => |interrupt_object| interrupt_object.shutdown(),
            .None => {},
        }
    }

    /// Drop and swap with null
    pub fn drop_and_swap(self: *@This()) void {
        self.drop();
        self.* = @This().None;
    }

    /// Borrow shareable reference. Increments refcount
    pub fn pack_shareable(self: *const @This()) !SharedObjectRef {
        switch (self.*) {
            .Stream, .InterruptObject => return error.ObjectNotShareable,
            .Endpoint => |endpoint| return SharedObjectRef{ .Endpoint = endpoint.ref.borrow() },
            .MemoryObject => |memory_obj_ref| return SharedObjectRef{ .MemoryObject = memory_obj_ref.borrow() },
            .LockedHandle => |locked_handle| return SharedObjectRef{ .LockedHandle = locked_handle.borrow() },
            .None => return SharedObjectRef.None,
        }
    }

    /// Unpack from shareable. Consumes ref, hence does not increment reference count
    pub fn unpack_shareable(ref: SharedObjectRef) @This() {
        switch (ref) {
            .Endpoint => |endpoint| return @This(){ .Endpoint = .{ .ref = endpoint, .is_owning = false } },
            .MemoryObject => |memory_obj_ref| return @This(){ .MemoryObject = memory_obj_ref },
            .LockedHandle => |locked_handle| return @This(){ .LockedHandle = locked_handle },
            .None => return @This().None,
        }
    }
};

/// Type of the object that can be passed with IPC
pub const SharedObjectType = enum {
    /// Shareable endpoint reference
    Endpoint,
    /// Shareable memory object reference
    MemoryObject,
    /// Shareable locked handle reference
    LockedHandle,
    /// Used to indicate that this reference cell is empty
    None,
};

/// Shareable reference to the object. Smaller than ObjectRef
/// as it doesn't store any local metadata. Can't store references
/// to non-shareable objects such as streams as well. Used in IPC
pub const SharedObjectRef = union(SharedObjectType) {
    /// Shareable reference to the endpoint
    Endpoint: *kepler.ipc.Endpoint,
    /// Shareable reference to the memory objects
    MemoryObject: kepler.memory.MemoryObjectRef,
    /// Shareable reference to the locked handle
    LockedHandle: *LockedHandle,
    /// Idk, just none :^)
    None: void,

    /// Drop reference
    pub fn drop(self: *const @This()) void {
        switch (self.*) {
            .Endpoint => |endpoint| endpoint.drop(),
            .LockedHandle => |locked_handle| locked_handle.drop(),
            .MemoryObject => |memory_obj_ref| memory_obj_ref.drop(),
            .None => {},
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
        OwnedByConsumer,
        /// Consumer has granted rights to read from cell. Now it can't do anything
        /// Producer is allowed to do one read and give rights back (aka burn after read)
        GrantedReadRights,
        /// Consumer has granted rights ro write to cell. Now it can't do anything
        /// Producer is allowed to do one write and give rights back (aka burn after write)
        GrantedWriteRights,
        /// Consumer can read value from this location and transfer to OwnedByConsumer state
        /// Producer has no rights
        ToBeReadByConsumer,
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
            ref.* = Cell{ .perms = .OwnedByConsumer, .ref = SharedObjectRef.None };
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
    /// 3) If perms == .OwnedByConsumer, asserts that cell points to null in debug mode
    fn check_bounds_and_status(self: *@This(), index: usize, perms: Permissions) !void {
        if (index > self.cells.len) {
            return error.OutOfBounds;
        }
        // Assert permission
        if (@atomicLoad(Permissions, &self.cells[index].perms, .Acquire) != perms) {
            return error.NotEnoughPermissions;
        }
        // Cells consumer has access to should always be nulled
        std.debug.assert(perms != .OwnedByConsumer or std.meta.activeTag(self.cells[index].ref) == .None);
    }

    /// Grant write rights. Invoked from consumer only
    pub fn grant_write(self: *@This(), index: usize) !void {
        try self.check_bounds_and_status(index, .OwnedByConsumer);
        @atomicStore(Permissions, &self.cells[index].perms, .GrantedWriteRights, .Release);
    }

    /// Assert permissions, read reference, modify permissions for a given cell
    fn read(self: *@This(), index: usize, old_perms: Permissions, new_perms: Permissions) !ObjectRef {
        // Assert perms
        try self.check_bounds_and_status(index, old_perms);
        // Move reference and set reference at this cell to None
        const result = ObjectRef.unpack_shareable(self.cells[index].ref);
        self.cells[index].ref = SharedObjectRef.None;
        // Modify perms
        @atomicStore(Permissions, &self.cells[index].perms, new_perms, .Release);
        return result;
    }

    /// Read reference from the consumer side at a given index
    pub fn read_from_consumer(self: *@This(), index: usize) !ObjectRef {
        return self.read(index, .ToBeReadByConsumer, .OwnedByConsumer);
    }

    /// Read reference from the producer side at a given index
    pub fn read_from_producer(self: *@This(), index: usize) !ObjectRef {
        return self.read(index, .GrantedReadRights, .OwnedByConsumer);
    }

    /// Write reference from consumer side
    pub fn write_from_consumer(self: *@This(), index: usize, object: ObjectRef) !void {
        try self.check_bounds_and_status(index, .OwnedByConsumer);
        self.cells[index].ref = try object.pack_shareable();
        @atomicStore(Permissions, &self.cells[index].perms, .GrantedReadRights, .Release);
    }

    /// Write reference from producer side
    pub fn write_from_producer(self: *@This(), index: usize, object: ObjectRef) !void {
        try self.check_bounds_and_status(index, .GrantedWriteRights);
        self.cells[index].ref = try object.pack_shareable();
        @atomicStore(Permissions, &self.cells[index].perms, .ToBeReadByConsumer, .Release);
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
    /// TODO: Consider storing allocator somewhere else, storing it here may
    /// be too wasteful. For now I just add it to pad it to 32 bytes :^)
    allocator: *std.mem.Allocator,

    pub fn create(allocator: *std.mem.Allocator, handle: usize, password: usize) !*LockedHandle {
        const instance = try allocator.create(@This());
        instance.ref_count = 1;
        instance.password = password;
        instance.handle = handle;
        return instance;
    }

    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.ref_count, .Add, 1, .AcqRel);
        return self;
    }

    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.ref_count, .Sub, 1, .AcqRel) > 1) {
            return;
        }
        self.allocator.destroy(self);
    }

    pub fn peek(self: *const @This(), password: usize) !usize {
        if (self.password != password) {
            return error.AuthenticationFailed;
        }
        return self.handle;
    }
};
