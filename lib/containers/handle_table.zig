usingnamespace @import("root").preamble;

/// HandleTable is the class for table of generic handles
/// It manages a map from integers to handles (type T)
/// TODO: Add more methods like dup2 and reserve
pub fn HandleTable(comptime T: type) type {
    return struct {
        /// Result type for a new cell allocation procedure.
        /// index - index in the table
        /// ref - reference to the memory for the handle
        pub const Location = struct { id: usize, ref: *T };

        /// We use max(usize) to indicate that there is no next member,
        /// as it is impossible for array to be that large
        const no_next = std.math.maxInt(usize);

        /// We use max(usize) - 1 to indicate that cell is in use
        const used_cell = std.math.maxInt(usize) - 1;

        /// Cell with handle and pointer to the next free slot
        const HandleCell = struct {
            /// Index of the next free cell
            next_free: usize,
            item: T,
        };

        /// Handle cells themselves
        cells: std.ArrayList(HandleCell),
        /// Index of the first free cell
        first_cell: usize,

        /// Create empty handle table
        pub fn init(allocator: *std.mem.Allocator) @This() {
            return .{
                .cells = std.ArrayList(HandleCell).init(allocator),
                .first_cell = no_next,
            };
        }

        /// Allocate a new cell for a new handle
        pub fn newCell(self: *@This()) !Location {
            std.debug.assert(self.first_cell != used_cell);
            if (self.first_cell == no_next) {
                // Increase dynarray length
                const pos = self.cells.items.len;
                const last = try self.cells.addOne();
                last.next_free = no_next;
                self.first_cell = pos;
            }
            const cell = &self.cells.items[self.first_cell];
            const index = self.first_cell;
            std.debug.assert(cell.next_free != used_cell);
            self.first_cell = cell.next_free;
            cell.next_free = used_cell;
            return Location{ .id = index, .ref = &cell.item };
        }

        /// Validate ID. Returns true if index is ID that was returned by newCell
        pub fn validateId(self: *const @This(), index: usize) bool {
            if (self.cells.items.len <= index) {
                return false;
            }
            if (self.cells.items[index].next_free != used_cell) {
                return false;
            }
            return true;
        }

        /// Free cell
        pub fn freeCell(self: *@This(), id: usize) !void {
            if (!self.validateId(id)) {
                return error.InvalidId;
            }
            self.cells.items[id].next_free = self.first_cell;
            self.first_cell = id;
        }

        /// Get access to handle data
        pub fn getData(self: *const @This(), id: usize) !*T {
            if (!self.validateId(id)) {
                return error.InvalidId;
            }
            return &self.cells.items[id].item;
        }

        /// Dispose handle array. Dispose handler is the struct with .dispose(loc: Location) method
        /// that is called for every remaining alive handle
        pub fn deinit(self: *@This(), comptime DisposerType: type, disposer: *DisposerType) void {
            comptime {
                if (!@hasDecl(DisposerType, "dispose")) {
                    @compileError("Disposer type should define \"dispose\" function");
                }
                const ExpectedDisposeType = fn (*DisposerType, Location) void;
                if (@TypeOf(DisposerType.dispose) != ExpectedDisposeType) {
                    @compileError("Invalid type of dispose function");
                }
            }
            for (self.cells.items) |*cell, id| {
                if (cell.next_free == used_cell) {
                    disposer.dispose(Location{ .ref = &cell.item, .id = id });
                }
            }
            self.cells.deinit();
        }
    };
}

/// Locked handle table is a wrapper on HandleTable that allows only one reader/writer using lock
pub fn LockedHandleTable(comptime T: type, comptime Lock: type) type {
    return struct {
        /// Location type that is reused from HandleTable
        pub const Location = HandleTable(T).Location;

        /// Handle table itself
        table: HandleTable(T),
        /// Protecting lock
        mutex: Lock = .{},

        /// Initialize LockedHandleTable
        pub fn init(allocator: *std.mem.Allocator) @This() {
            return .{ .table = HandleTable(T).init(allocator) };
        }

        /// Allocate a new cell for a new handle and
        /// leave the table locked
        /// NOTE: Don't forget to call unlock lol :^)
        pub fn newCellNolock(self: *@This()) !Location {
            return self.table.newCell();
        }

        /// Free cell without holding the lock
        pub fn freeCellNolock(self: *@This(), id: usize) !void {
            return self.table.freeCell(id);
        }

        /// Get cell data and leave the table locked
        pub fn getDataNolock(self: *@This(), id: usize) !*T {
            return self.table.getData(id);
        }

        /// Deinitialize the table
        pub fn deinit(self: *@This(), comptime DisposerType: type, disposer: *DisposerType) void {
            self.table.deinit(DisposerType, disposer);
        }

        /// Lock the table
        pub fn lock(self: *@This()) void {
            self.mutex.lock();
        }

        /// Unlock the table
        pub fn unlock(self: *@This()) void {
            self.mutex.unlock();
        }
    };
}

test "handle_table" {
    var instance = HandleTable(u64).init(std.testing.allocator);

    const result1 = try instance.newCell();
    result1.ref.* = 69;
    std.testing.expect(result1.id == 0);

    const result2 = try instance.newCell();
    result2.ref.* = 420;
    std.testing.expect(result2.id == 1);

    if (instance.getData(2)) {
        unreachable;
    } else |err| {
        std.testing.expect(err == error.InvalidId);
    }
    std.testing.expect((try instance.getData(0)).* == 69);

    try instance.freeCell(0);
    if (instance.getData(0)) {
        unreachable;
    } else |err| {
        std.testing.expect(err == error.InvalidId);
    }

    std.testing.expect((try instance.getData(1)).* == 420);

    const TestDisposer = struct {
        called: bool,

        fn init() @This() {
            return .{ .called = false };
        }

        fn dispose(self: *@This(), loc: HandleTable(u64).Location) void {
            std.debug.assert(!self.called);
            std.debug.assert(loc.id == 1);
            std.debug.assert(loc.ref.* == 420);
            self.called = true;
        }
    };

    var disposer = TestDisposer.init();
    instance.deinit(TestDisposer, &disposer);
    std.testing.expect(disposer.called);
}
