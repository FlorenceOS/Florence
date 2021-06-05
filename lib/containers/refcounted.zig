usingnamespace @import("root").preamble;

/// Creates a refcounted version of the object
pub fn RefCounted(comptime T: type, comptime dispose_handler: ?(fn (*T) void)) type {
    return struct {
        /// Reference count
        ref_count: usize,
        /// The type itself
        data: T,
        /// Allocator used to allocate the object
        allocator: *std.mem.Allocator,

        /// Allocate a refcounted object using passed allocator and set reference
        /// count to 1
        pub fn create(allocator: *std.mem.Allocator, value: T) !*@This() {
            const result = try allocator.create(@This());
            result.data = value;
            result.ref_count = 1;
            result.allocator = allocator;
            return result;
        }

        /// Borrow reference to the existing refcounted object
        pub fn borrow(self: *@This()) *@This() {
            _ = @atomicRmw(usize, &self.ref_count, .Add, 1, .AcqRel);
            return self;
        }

        /// Drop existing reference to the refcounted object
        pub fn drop(self: *@This()) void {
            if (@atomicRmw(usize, &self.ref_count, .Sub, 1, .AcqRel) == 1) {
                if (comptime dispose_handler) |handler| {
                    handler(&self.data);
                }
                self.allocator.destroy(self);
            }
        }
    };
}

test "RefCounted" {
    var test_var: usize = 2;
    const TestType = RefCounted(usize, struct {
        fn destructor(self: *usize) void {
            const pointer = @intToPtr(*usize, self.*);
            pointer.* = 1;
        }
    }.destructor);

    const val = TestType.create(std.testing.allocator, @ptrToInt(&test_var)) catch {
        @panic("Failed to allocate");
    };

    std.debug.assert(test_var == 2);
    const val2 = val.borrow();
    std.debug.assert(test_var == 2);
    val.drop();
    std.debug.assert(test_var == 2);
    val2.drop();
    std.debug.assert(test_var == 1);
}
