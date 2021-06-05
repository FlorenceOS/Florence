const os = @import("root").os;
const lib = @import("root").lib;

pub var bsp_task: os.thread.Task = .{};

const TPIDR_EL1 = os.platform.msr(*os.platform.smp.CoreData, "TPIDR_EL1");

pub const CoreData = struct {
    pub fn start_monitoring(self: *@This()) void {}

    pub fn wait(self: *@This()) void {
        os.platform.spin_hint();
    }

    pub fn ring(self: *@This()) void {}
};

pub const sched_stack_size = 0x10000;
pub const int_stack_size = 0x10000;
pub const task_stack_size = 0x10000;
pub const stack_guard_size = 0x1000;
pub const ap_init_stack_size = 0x4000;

pub fn get_current_cpu() *os.platform.smp.CoreData {
    return TPIDR_EL1.read();
}

pub fn set_current_cpu(ptr: *os.platform.smp.CoreData) void {
    TPIDR_EL1.write(ptr);
}

pub const TaskData = struct {
    pub fn load_state(self: *@This()) void {
        const cpu = os.platform.thread.get_current_cpu();
    }
};

pub fn sched_call_impl(fun: usize, ctx: usize) void {
    asm volatile (
        \\SVC #'S'
        :
        : [_] "{X2}" (fun),
          [_] "{X1}" (ctx)
    );
}

pub fn init_task_call(new_task: *os.thread.Task, entry: *os.thread.NewTaskEntry) !void {
    const cpu = os.platform.thread.get_current_cpu();

    new_task.registers.pc = @ptrToInt(entry.function);
    new_task.registers.x0 = @ptrToInt(entry);
    new_task.registers.sp = lib.util.libalign.align_down(usize, 16, @ptrToInt(entry));
    new_task.registers.spsr = 0b0100; // EL1t / EL1 with SP0
}

pub fn self_exited() ?*os.thread.Task {
    const curr = os.platform.get_current_task();

    if (curr == &bsp_task)
        return null;

    return curr;
}
