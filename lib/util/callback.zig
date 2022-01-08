const std = @import("std");

pub fn Callback(
    comptime ReturnType: type,
    comptime ArgType: type,
    comptime inline_capacity: usize,
    comptime deinitable: bool,
) type {
    return struct {
        callFn: fn (*anyopaque, ArgType) ReturnType,
        deinitFn: if (deinitable) fn (*anyopaque) void else void,
        inline_data: [inline_capacity]u8,

        pub const callback_inline_capacity = inline_capacity;
        pub const callback_deinitable = deinitable;
        pub const CallbackReturnType = ReturnType;
        pub const CallbackArgType = ArgType;

        pub inline fn call(self: *const @This(), arg: ArgType) ReturnType {
            return self.callFn(self.context(), arg);
        }

        pub inline fn deinit(self: *const @This()) void {
            if (comptime (!deinitable))
                @compileError("Cannot deinit() this!");
            self.deinitFn(self.context());
        }

        pub inline fn context(self: *const @This()) *anyopaque {
            return @intToPtr(*anyopaque, @ptrToInt(&self.inline_data[0]));
        }
    };
}

fn heapAllocatedCallback(
    comptime CallbackType: type,
    thing_to_callback: anytype,
    allocator: std.mem.Allocator,
) !CallbackType {
    const callback_inline_capacity = CallbackType.callback_inline_capacity;
    const CallbackReturnType = CallbackType.CallbackReturnType;
    const CallbackArgType = CallbackType.CallbackArgType;

    // What can we fit in the inline storage?
    if (comptime (callback_inline_capacity < @sizeOf(usize))) {
        @compileError("Not enough inline capacity to heap allocate, can't fit the heap pointer!");
    }

    const allocator_inline = callback_inline_capacity >= @sizeOf(usize) + @sizeOf(std.mem.Allocator);

    const HeapAllocBlock = struct {
        alloc: if (allocator_inline) void else std.mem.Allocator,
        value: @TypeOf(thing_to_callback),
    };

    return inlineAllocatedCallback(CallbackType, try struct {
        heap_block: *HeapAllocBlock,
        inline_allocator: if (allocator_inline) std.mem.Allocator else void,

        fn init(alloc: std.mem.Allocator, thing: anytype) !@This() {
            const heap_block = try alloc.create(HeapAllocBlock);
            if (comptime (!allocator_inline)) heap_block.alloc = alloc;
            heap_block.value = thing;
            return @This(){
                .heap_block = heap_block,
                .inline_allocator = if (comptime (allocator_inline)) alloc else {},
            };
        }

        fn allocator(self: *const @This()) callconv(.Inline) std.mem.Allocator {
            if (comptime (allocator_inline))
                return self.inline_allocator;
            return self.heap_block.alloc;
        }

        fn call(self: *const @This(), arg: CallbackArgType) CallbackReturnType {
            return @call(.{ .modifier = .always_inline }, self.heap_block.value.call, .{arg});
        }

        fn deinit(self: *const @This()) void {
            if (@hasDecl(@TypeOf(self.heap_block.value), "deinit"))
                @call(.{ .modifier = .always_inline }, self.heap_block.value.deinit, .{});
            self.allocator().destroy(self.heap_block);
        }
    }.init(allocator, thing_to_callback));
}

pub fn inlineAllocatedCallback(
    comptime CallbackType: type,
    thing_to_callback: anytype,
) CallbackType {
    const TTC = @TypeOf(thing_to_callback);
    if (@sizeOf(TTC) > CallbackType.callback_inline_capacity) {
        @compileError("Cannot fit this object in the inline capacity!");
    }

    var result: CallbackType = undefined;
    std.mem.copy(u8, result.inline_data[0..], std.mem.asBytes(&thing_to_callback));

    if (comptime (@hasDecl(TTC, "call"))) {
        const ReturnType = CallbackType.CallbackReturnType;
        const ArgType = CallbackType.CallbackArgType;

        result.callFn = struct {
            fn caller(ctx_ptr: *anyopaque, arg: ArgType) ReturnType {
                if(comptime(@sizeOf(TTC) == 0)) {
                    return @call(.{.modifier = .always_inline}, TTC.call, .{{}, arg});
                } else {
                    const ctx = @ptrCast(*TTC, @alignCast(@alignOf(TTC), ctx_ptr));
                    return @call(.{.modifier = .always_inline}, TTC.call, .{ctx, arg});
                }
            }
        }.caller;
    }

    if (comptime (CallbackType.callback_deinitable)) {
        if (comptime (@hasDecl(@TypeOf(thing_to_callback), "deinit"))) {
            result.deinitFn = struct {
                fn deinit(ctx_ptr: *anyopaque) void {
                    if(comptime(@sizeOf(TTC) == 0)) {
                        return @call(.{.modifier = .always_inline}, TTC.deinit, .{{}});
                    } else {
                        const ctx = @ptrCast(*TTC, @alignCast(@alignOf(TTC), ctx_ptr));
                        return @call(.{.modifier = .always_inline}, TTC.deinit, .{ctx});
                    }
                }
            }.deinit;
        } else {
            result.deinitFn = struct {
                fn f(_: *anyopaque) void {}
            }.f;
        }
    }

    return result;
}

pub fn possiblyHeapAllocatedCallback(
    comptime CallbackType: type,
    thing_to_callback: anytype,
    allocator: std.mem.Allocator,
) !CallbackType {
    if (comptime (CallbackType.callback_inline_capacity) < @sizeOf(@TypeOf(thing_to_callback))) {
        return heapAllocatedCallback(CallbackType, thing_to_callback, allocator);
    }
    return inlineAllocatedCallback(CallbackType, thing_to_callback);
}

test "Callbacks" {
    const CallbackT = Callback(usize, usize, 8, true);

    var cb = inlineAllocatedCallback(CallbackT, struct {
        value: usize,

        fn call(self: *@This(), a: usize) usize {
            return self.value + a;
        }

        fn deinit(self: *@This()) void {
            self.value = 0;
        }
    }{
        .value = 4,
    });

    try std.testing.expect(cb.call(5) == 9);
    try std.testing.expect(cb.call(3) == 7);

    cb.deinit();

    try std.testing.expect(cb.call(5) == 5);

    cb = inlineAllocatedCallback(CallbackT, struct {
        value: usize,

        fn call(self: *@This(), a: usize) usize {
            self.value += 1;
            return self.value + a;
        }

        fn deinit(self: *@This()) void {
            self.value = 0;
        }
    }{
        .value = 4,
    });

    try std.testing.expect(cb.call(5) == 10);
    try std.testing.expect(cb.call(5) == 11);
    try std.testing.expect(cb.call(5) == 12);

    cb.deinit();

    try std.testing.expect(cb.call(5) == 6);

    cb = try heapAllocatedCallback(CallbackT, struct {
        v1: usize,
        v2: usize,
        v3: usize,

        fn call(self: *@This(), a: usize) usize {
            self.v1 += 1;
            self.v2 = a;
            self.v3 = self.v1 ^ self.v2;

            return self.v3;
        }

        fn deinit(_: *@This()) void { }
    }{
        .v1 = 4,
        .v2 = 1,
        .v3 = undefined,
    }, std.testing.allocator);

    try std.testing.expect(cb.call(5) == 0);
    try std.testing.expect(cb.call(5) == 6 ^ 5);

    cb.deinit();
}
