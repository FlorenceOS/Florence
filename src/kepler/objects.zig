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
    /// Used to indicate that this reference cell is empty
    None,
};

/// Type that represents reference to the object
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
    MemoryObject: struct {
        /// Reference to the memory object itself
        ref: *kepler.memory.MemoryObject,
        /// null if memory object was not mapped
        /// address of the mapping
        mapped_to: ?usize,
        /// Mapper that was used to map the object
        /// null if this object is a sharable reference
        mapper: ?*kepler.memory.Mapper,
    },
    /// None means that there is no reference to any object
    None: void,

    /// Drop reference
    pub fn drop(self: @This()) void {
        switch (self) {
            .Stream => |stream| {
                stream.ref.abandon(stream.peer);
            },
            .Endpoint => |endpoint| {
                if (endpoint.is_owning) {
                    endpoint.ref.shutdown();
                } else {
                    endpoint.ref.drop();
                }
            },
            .MemoryObject => |memory_object| {
                if (memory_object.mapped_to) |offset| {
                    std.debug.assert(memory_object.mapper != null);
                    memory_object.mapper.?.unmap(memory_object.ref, offset);
                }
            },
            .None => {},
        }
    }

    /// Drop and swap with null
    pub fn drop_and_swap(self: *@This()) void {
        self.drop();
        self.* = @This().None;
    }

    /// Borrow shareable reference
    pub fn borrow_shareable(self: @This()) !@This() {
        switch (self) {
            .Stream => return error.NotShareable,
            .Endpoint => |endpoint| return ObjectRef{ .Endpoint = .{ .ref = endpoint.ref.borrow(), .is_owning = false } },
            .MemoryObject => |memory_object| return ObjectRef{ .MemoryObject = .{ .ref = memory_object.ref.borrow(), .mapped_to = null, .mapper = null } },
            .None => return .None,
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
        ref: ObjectRef,
    };

    /// Array of cells
    cells: []Cell,
    /// Allocator used to allocate this object
    allocator: *std.mem.Allocator,
    /// Reference count
    ref_count: usize,

    /// Create shared memory object
    pub fn create(allocator: *std.mem.Allocator, num: usize) !*@This() {
        const instance = try allocator.create(@This());
        errdefer allocator.destroy(instance);

        instance.cells = try allocator.alloc(Cell, num);
        for (instance.cells) |*ref| {
            // Initially consumer owns every cell, as it is the one that
            // initiates requests
            ref.* = Cell{ .perms = .OwnedByConsumer, .ref = ObjectRef.None };
        }

        instance.allocator = allocator;
        instance.ref_count = 1;

        return instance;
    }

    /// Borrow reference to SharedRefArray object
    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.ref_count, .Add, 1, .AcqRel);
    }

    /// Drop reference to SharedRefArray object
    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.ref_count, .Sub, 1, .AcqRel) > 1) {
            return;
        }
        for (self.refs) |*ref| {
            ref.drop();
        }
        self.allocator.free(self.refs);
        self.allocator.destroy(self);
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
        const result = self.cells[index].ref;
        self.cells[index].ref = ObjectRef.None;
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
        self.cells[index].ref = try object.borrow_shareable();
        @atomicStore(Permissions, &self.cells[index].perms, .GrantedReadRights, .Release);
    }

    /// Write reference from producer side
    pub fn write_from_producer(self: *@This(), index: usize, object: ObjectRef) !void {
        try self.check_bounds_and_status(index, .GrantedWriteRights);
        self.cells[index].ref = try object.borrow_shareable();
        @atomicStore(Permissions, &self.cells[index].perms, .ToBeReadByConsumer, .Release);
    }  
};
