usingnamespace @import("root").preamble;

/// Reference is a pointer to the kepler object
pub const Reference = union(enum) {
    mailbox: *os.kepler.notifications.Mailbox,
    caller: *os.kepler.rpc.Caller,
    callee_borrowed: *os.kepler.rpc.Callee,
    callee_owning: *os.kepler.rpc.Callee,

    /// Borrow reference
    pub fn borrow(self: @This()) !@This() {
        return switch (self) {
            .callee_borrowed => |val| @This(){ .callee_borrowed = val.borrowConsumer() },
            else => error.NotBorrowable,
        };
    }

    /// Drop reference
    pub fn drop(self: @This()) void {
        switch (self) {
            .mailbox => |mailbox| mailbox.shutdown(),
            .caller => |caller| caller.shutdown(),
            .callee_borrowed => |borrowed| borrowed.dropBorrowed(),
            .callee_owning => |owning| owning.dropOwning(),
        }
    }
};

/// Kepler references table type
const RefTable = lib.containers.handle_table.LockedHandleTable(Reference, os.thread.Mutex);

/// Universe is an addressable collection of references
pub const Universe = struct {
    /// Handle disposer
    const Disposer = struct {
        pub fn dispose(self: *@This(), loc: RefTable.Location) void {
            loc.ref.drop();
        }
    };

    /// Reference count
    refcount: usize = 1,
    /// Allocator used to allocate the universe
    allocator: *std.mem.Allocator,
    /// Handle table
    table: RefTable,

    /// Create new universe
    pub fn create(allocator: *std.mem.Allocator) !*@This() {
        const result = try allocator.create(@This());
        result.* = .{
            .allocator = allocator,
            .table = RefTable.init(allocator),
        };
        return result;
    }

    /// Borrow reference to the universe
    pub fn borrow(self: *@This()) *@This() {
        _ = @atomicRmw(usize, &self.refcount, .Add, 1, .AcqRel);
    }

    /// Drop reference to the universe
    pub fn drop(self: *@This()) void {
        if (@atomicRmw(usize, &self.refcount, .Sub, 1, .AcqRel) == 1) {
            self.table.deinit(Disposer, Disposer{});
            self.allocator.destroy(self);
        }
    }

    /// Lock universe
    pub fn lock(self: *@This()) void {
        self.table.lock();
    }

    /// Unlock universe
    pub fn unlock(self: *@This()) void {
        self.table.unlock();
    }

    /// Put new reference in the universe (should be locked)
    pub fn putNolock(self: *@This(), ref: Reference) !usize {
        const cell = try self.table.newCellNolock();
        cell.ref.* = ref;
        return cell.id;
    }

    /// Take reference at index
    pub fn takeAtNolock(self: *@This(), index: usize) !Reference {
        const refptr = try self.table.getDataNolock(index);
        const res = refptr.*;
        self.table.freeCellNolock(index) catch unreachable;
        return res;
    }

    /// Drop reference at index (should be locked)
    pub fn dropAtNolock(self: *@This(), index: usize) !void {
        const refptr = try self.table.getDataNolock(index);
        refptr.drop();
        self.table.freeCellNolock(index) catch unreachable;
    }

    /// Get mailbox at position (should be locked)
    pub fn getMailboxAtNolock(self: *@This(), index: usize) !*os.kepler.notifications.Mailbox {
        const refptr = try self.table.getDataNolock(index);
        return switch (refptr.*) {
            .mailbox => |mailbox| mailbox,
            else => error.InvalidHandleType,
        };
    }

    /// Borrow mailbox at position (should be locked)
    pub fn borrowMailboxAtNolock(self: *@This(), index: usize) !*os.kepler.notifications.Mailbox {
        return (try self.getMailboxAtNolock(index)).borrow();
    }

    /// Get caller at position (should be locked)
    pub fn getCallerAtNolock(self: *@This(), index: usize) !*os.kepler.rpc.Caller {
        const refptr = try self.table.getDataNolock(index);
        return switch (refptr.*) {
            .caller => |caller| caller,
            else => error.InvalidHandleType,
        };
    }

    /// Borrow caller at position (should be locked)
    pub fn borrowCallerAtNolock(self: *@This(), index: usize) !*os.kepler.rpc.Caller {
        return (try self.getCallerAtNolock(index)).borrow();
    }

    /// Get owning callee ref at position (should be locked)
    pub fn getOwningCalleeNolock(self: *@This(), index: usize) !*os.kepler.rpc.Callee {
        const refptr = try self.table.getDataNolock(index);
        return switch (refptr.*) {
            .callee_owning => |callee| callee,
            else => error.InvalidHandleType,
        };
    }

    /// Borrow owning callee ref at position (should be locked)
    pub fn borrowOwningCalleeAtNolock(self: *@This(), index: usize) !*os.kepler.rpc.Callee {
        return (try self.getOwningCalleeNolock(index)).borrowOwning();
    }

    /// Get borrowed callee ref at position (should be locked)
    pub fn getBorrowedCalleeNolock(self: *@This(), index: usize) !*os.kepler.rpc.Callee {
        const refptr = try self.table.getDataNolock(index);
        return switch (refptr.*) {
            .callee_borrowed => |callee| callee,
            else => error.InvalidHandleType,
        };
    }

    /// Borrow borrowed callee ref at position (should be locked)
    pub fn borrowBorrowedCalleeAtNolock(self: *@This(), index: usize) !*os.kepler.rpc.Callee {
        return (try self.getBorrowedCalleeNolock(index)).borrowConsumer();
    }
};
