usingnamespace @import("root").preamble;
const StackTrace = std.builtin.StackTrace;

var panic_counter: usize = 0;

pub fn breakpoint_panic(message: []const u8, stack_trace: ?*StackTrace) callconv(.Inline) noreturn {
    @breakpoint();
    unreachable;
}

pub fn panic(message: []const u8, stack_trace: ?*StackTrace) noreturn {
    const panic_num = @atomicRmw(usize, &panic_counter, .Add, 1, .AcqRel) + 1;

    const cpu = os.platform.thread.get_current_cpu();
    cpu.panicked = true;
    const cpu_id = cpu.id();

    if (config.kernel.panic_once and panic_num != 1) {
        os.platform.hang();
    }

    os.log("PANIC {}: CPU {}: {s}!\n", .{ panic_num, cpu_id, message });

    if (stack_trace) |trace| {
        os.log("TODO: print stack trace.\nI bet this is very helpful. No problem.\n", .{});
        os.kernel.debug.dumpStackTrace(trace);
    } else {
        os.log("idfk I didn't get a stack trace.\n", .{});
    }

    os.platform.hang();
}
