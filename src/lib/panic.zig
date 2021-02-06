const StackTrace = @import("builtin").StackTrace;

const os = @import("root").os;

pub fn breakpoint_panic(message: ?[]const u8, stack_trace: ?*StackTrace) noreturn {
    @breakpoint();
    unreachable;
}

var panic_counter: usize = 0;
/// You only panic once
const YOPO = false;

pub fn panic(message_in: ?[]const u8, stack_trace: ?*StackTrace) noreturn {
    const panic_num = @atomicRmw(usize, &panic_counter, .Add, 1, .AcqRel) + 1;

    const cpu = os.platform.get_current_cpu();
    cpu.panicked = true;
    const cpu_id = cpu.id();
    const message: []const u8 = message_in orelse "no message";

    if(YOPO and panic_num != 1)
        os.platform.hang();

    os.log("PANIC {}: CPU {}: {}!\n", .{panic_num, cpu_id, message});

    if (stack_trace) |trace| {
        os.log("TODO: print stack trace.\nI bet this is very helpful. No problem.\n", .{});
        os.lib.debug.dump_stack_trace(trace);
    } else {
        os.log("idfk I didn't get a stack trace.\n", .{});
    }

    os.platform.hang();
}
