const std = @import("std");

pub fn Callback(
    comptime ReturnType: type,
    comptime ArgType: type,
    comptime inline_capacity: usize,
    comptime deinitable: bool,
) type {
    return struct {
        callFn: fn (usize, ArgType) ReturnType,
        deinitFn: if (deinitable) fn (usize) void else void,
        inline_data: [inline_capacity]u8,

        pub const callback_inline_capacity = inline_capacity;
        pub const callback_deinitable = deinitable;
        pub const CallbackReturnType = ReturnType;
        pub const CallbackArgType = ArgType;

        pub fn call(self: *const @This(), arg: ArgType) callconv(.Inline) ReturnType {
            return self.callFn(self.context(), arg);
        }

        pub fn deinit(self: *const @This()) callconv(.Inline) void {
            if (comptime (!deinitable))
                @compileError("Cannot deinit() this!");
            self.deinitFn(self.context());
        }

        pub fn context(self: *const @This()) callconv(.Inline) usize {
            return @ptrToInt(&self.inline_data[0]);
        }
    };
}

fn heapAllocatedCallback(
    comptime CallbackType: type,
    thing_to_callback: anytype,
    allocator: *std.mem.Allocator,
) !CallbackType {
    const callback_inline_capacity = CallbackType.callback_inline_capacity;
    const CallbackReturnType = CallbackType.CallbackReturnType;
    const CallbackArgType = CallbackType.CallbackArgType;

    // What can we fit in the inline storage?
    if (callback_inline_capacity < @sizeOf(usize)) {
        @compileError("Not enough inline capacity to heap allocate, can't fit the heap pointer!");
    }

    const allocator_inline = callback_inline_capacity >= @sizeOf(usize) * 2;

    const HeapAllocBlock = struct {
        alloc: if (allocator_inline) void else *std.mem.Allocator,
        value: @TypeOf(thing_to_callback),
    };

    return inlineAllocatedCallback(CallbackType, try struct {
        heap_block: *HeapAllocBlock,
        inline_allocator: if (allocator_inline) *std.mem.Allocator else void,

        fn init(alloc: *std.mem.Allocator, thing: anytype) !@This() {
            const heap_block = try alloc.create(HeapAllocBlock);
            if (comptime (!allocator_inline)) heap_block.alloc = alloc;
            heap_block.value = thing;
            return @This(){
                .heap_block = heap_block,
                .inline_allocator = if (comptime (allocator_inline)) alloc else {},
            };
        }

        fn allocator(self: *const @This()) callconv(.Inline) *std.mem.Allocator {
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
    if (@sizeOf(@TypeOf(thing_to_callback)) > CallbackType.callback_inline_capacity) {
        @compileError("Cannot fit this object in the inline capacity!");
    }

    // WARNING: TYPE PUNNING AHEAD
    var result: CallbackType = undefined;
    std.mem.copy(u8, result.inline_data[0..], std.mem.asBytes(&thing_to_callback));

    if (!@hasDecl(@TypeOf(thing_to_callback), "call"))
        @compileError("Missing `call` declaration on " ++ @typeName(@TypeOf(thing_to_callback)) ++ "! Are you missing `pub`?");

    if (comptime (@hasDecl(@TypeOf(thing_to_callback), "call"))) {
        const CallType = @TypeOf(@TypeOf(thing_to_callback).call);
        const ReturnType = CallbackType.CallbackReturnType;
        const ArgType = CallbackType.CallbackArgType;
        // zig fmt: off
        if(CallType != fn(*@TypeOf(thing_to_callback), ArgType) ReturnType and
           CallType != fn(*const @TypeOf(thing_to_callback), ArgType) ReturnType
        // zig fmt: on
        ) {
            @compileError("Bad call function signature on " ++ @typeName(@TypeOf(thing_to_callback)) ++ "!");
        }
        result.callFn = @intToPtr(fn (usize, ArgType) ReturnType, @ptrToInt(@TypeOf(thing_to_callback).call));
    } else {
        @compileError("Missing call function on " ++ @typeName(@TypeOf(thing_to_callback)) ++ "! Are you missing `pub`?");
    }

    if (comptime (CallbackType.callback_deinitable)) {
        if (comptime (@hasDecl(@TypeOf(thing_to_callback), "deinit"))) {
            const DeinitType = @TypeOf(@TypeOf(thing_to_callback).deinit);
            // zig fmt: off
            if(DeinitType != fn(*@TypeOf(thing_to_callback)) void and
               DeinitType != fn(*const @TypeOf(thing_to_callback)) void
            // zig fmt: on
            ) {
                @compileError("Bad deinit function signature on " ++ @typeName(@TypeOf(thing_to_callback)) ++ "!");
            }
            result.deinitFn = @intToPtr(fn (usize) void, @ptrToInt(@TypeOf(thing_to_callback).deinit));
        } else {
            result.deinitFn = struct {
                fn f(_: usize) void {}
            }.f;
        }
    }

    return result;
}

pub fn possiblyHeapAllocatedCallback(
    comptime CallbackType: type,
    thing_to_callback: anytype,
    allocator: *std.mem.Allocator,
) !CallbackType {
    if (comptime (CallbackType.callback_inline_capacity) < @sizeOf(@TypeOf(thing_to_callback))) {
        return heapAllocatedCallback(CallbackType, thing_to_callback, allocator);
    }
    return inlineAllocatedCallback(CallbackType, thing_to_callback);
}
