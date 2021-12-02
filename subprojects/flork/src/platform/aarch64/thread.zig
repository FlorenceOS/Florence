const os = @import("root").os;

pub var bsp_task: os.thread.Task = .{
    .name = "BSP task",
};

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
    pub fn loadState(self: *@This()) void {
        const cpu = os.platform.thread.get_current_cpu();
    }
};

pub fn sched_call_impl(fun: usize, ctx: usize) void {
    asm volatile (
        \\SVC #'S'
        :
        : [_] "{X2}" (fun),
          [_] "{X1}" (ctx)
        : "memory"
    );
}

pub fn enter_userspace(entry: u64, arg: u64, stack: u64) noreturn {
    asm volatile (
        \\ MOV SP, %[stack]
        \\ MSR ELR_EL1, %[entry]
        \\ MOV X1, #0
        \\ MSR SPSR_EL1, X1
        \\
        \\ MOV X2, #0
        \\ MOV X3, #0
        \\ MOV X4, #0
        \\ MOV X5, #0
        \\ MOV X6, #0
        \\ MOV X7, #0
        \\ MOV X8, #0
        \\ MOV X9, #0
        \\ MOV X10, #0
        \\ MOV X11, #0
        \\ MOV X12, #0
        \\ MOV X13, #0
        \\ MOV X14, #0
        \\ MOV X15, #0
        \\ MOV X16, #0
        \\ MOV X17, #0
        \\ MOV X18, #0
        \\ MOV X19, #0
        \\ MOV X20, #0
        \\ MOV X21, #0
        \\ MOV X22, #0
        \\ MOV X23, #0
        \\ MOV X24, #0
        \\ MOV X25, #0
        \\ MOV X26, #0
        \\ MOV X27, #0
        \\ MOV X28, #0
        \\ MOV X29, #0
        \\ MOV X30, #0
        \\
        \\ ERET
        \\
        :
        : [arg] "{X0}" (arg),
          [stack] "r" (stack),
          [entry] "r" (entry)
    );
    unreachable;
}

pub fn init_task_call(new_task: *os.thread.Task, entry: *os.thread.NewTaskEntry) !void {
    const cpu = os.platform.thread.get_current_cpu();

    new_task.registers.pc = @ptrToInt(entry.function);
    new_task.registers.x0 = @ptrToInt(entry);
    new_task.registers.sp = lib.util.libalign.alignDown(usize, 16, @ptrToInt(entry));
    new_task.registers.spsr = 0b0100; // EL1t / EL1 with SP0
}

pub fn self_exited() ?*os.thread.Task {
    const curr = os.platform.get_current_task();

    if (curr == &bsp_task)
        return null;

    return curr;
}
