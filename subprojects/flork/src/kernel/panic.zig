const os = @import("root").os;
const StackTrace = @import("std").builtin.StackTrace;

var panic_counter: usize = 0;

const log = @import("lib").output.log.scoped(.{
    .prefix = "kernel/panic",
    .filter = null,
}).write;

pub inline fn breakpoint_panic(message: []const u8, stack_trace: ?*StackTrace) noreturn {
    _ = message;
    _ = stack_trace;
    @breakpoint();
    unreachable;
}

pub fn panic(message: []const u8, stack_trace: ?*StackTrace) noreturn {
    const panic_num = @atomicRmw(usize, &panic_counter, .Add, 1, .AcqRel) + 1;

    const cpu = os.platform.thread.get_current_cpu();
    cpu.panicked = true;
    const cpu_id = cpu.id();

    if (@import("config").kernel.panic_once and panic_num != 1) {
        os.platform.hang();
    }

    log(null, "Panic #{d}: CPU {d}: {s}!", .{ panic_num, cpu_id, message });
    log(null, "Currently executing task: {s}", .{os.platform.get_current_task().name});
    if (os.platform.get_current_task().secondary_name) |n| {
        log(null, "Task secondary name: {s}", .{n});
    }

    log(null, "Error trace:", .{});
    if (stack_trace) |trace| {
        os.kernel.debug.dumpStackTrace(trace);
    } else {
        log(null, "None", .{});
    }

    log(null, "Current stack trace:", .{});
    os.kernel.debug.dumpCurrentTrace();

    os.platform.hang();
}
