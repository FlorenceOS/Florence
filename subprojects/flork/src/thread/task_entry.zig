const os = @import("root").os;

const std = @import("std");
const lib = @import("lib");

const log = lib.output.log.scoped(.{
    .prefix = "NewTaskEntry",
    .filter = .info,
}).write;

const libalign = lib.util.libalign;

/// Class that handles calling a function with any arguments on a new stack
/// Used as a helper for task creation in platform-specific code
pub const NewTaskEntry = struct {
    /// Callback that should be executed in a new task
    function: fn (*NewTaskEntry) noreturn,

    pub fn alloc(task: *os.thread.Task, func: anytype, args: anytype) *NewTaskEntry {
        const Args = @TypeOf(args);
        const Func = @TypeOf(func);

        // Method: specify subtype with specific types of func and args
        const Wrapper = struct {
            entry: NewTaskEntry = .{ .function = invoke },
            function: Func,
            args: Args,

            /// Error guard
            fn callWithErrorGuard(self: *@This()) !void {
                return @call(.{}, self.function, self.args);
            }

            /// Implementation of invoke
            fn invoke(entry: *NewTaskEntry) noreturn {
                const self = @fieldParentPtr(@This(), "entry", entry);
                self.callWithErrorGuard() catch |err| {
                    log(null, "Task has finished with error {e}\n", .{err});
                };
                os.thread.scheduler.exitTask();
            }

            /// Creates Wrapper on the stack
            fn create(
                function: anytype,
                arguments: anytype,
                boot_stack_top: usize,
                boot_stack_bottom: usize,
            ) *@This() {
                const addr = libalign.alignDown(
                    usize,
                    @alignOf(@This()),
                    boot_stack_top - @sizeOf(@This()),
                );
                std.debug.assert(addr > boot_stack_bottom);
                const wrapper_ptr = @intToPtr(*@This(), addr);
                wrapper_ptr.* = .{
                    .function = function,
                    .args = arguments,
                };
                return wrapper_ptr;
            }
        };

        const stack_top = task.stack;
        const stack_bottom = stack_top - os.platform.thread.task_stack_size;

        return &Wrapper.create(func, args, stack_top, stack_bottom).entry;
    }
};
