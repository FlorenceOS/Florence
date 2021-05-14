const os = @import("root").os;

/// Switch to the next task from the current one
fn yield_to(frame: *os.platform.InterruptFrame, task: *os.thread.Task) void {
    const cpu = os.platform.thread.get_current_cpu();
    const current_task = os.platform.get_current_task();

    current_task.registers = frame.*;
    frame.* = task.registers;
    os.platform.set_current_task(task);
    if (current_task.paging_context != task.paging_context) {
        task.paging_context.apply();
    }

    task.platform_data.load_state();
}

/// Yield to the next task or stay in the same task
/// if there is no next task. Use in timers
pub fn yield_or_not(frame: *os.platform.InterruptFrame) void {
    const cpu = os.platform.thread.get_current_cpu();
    if (cpu.executable_tasks.try_dequeue()) |task| {
        yield_to(frame, task);
    }
}

/// Wait for queue to become non-empty and yield to the next task
/// Use for yield. Empty usize argument is needed so that
/// this function could be passed to os.platform.sched_call
pub fn wait_yield(frame: *os.platform.InterruptFrame, _: usize) void {
    const cpu = os.platform.thread.get_current_cpu();
    yield_to(frame, cpu.executable_tasks.dequeue());
}

/// Wait for the task on bootstrap
pub fn bootstrap(frame: *os.platform.InterruptFrame) void {
    const cpu = os.platform.thread.get_current_cpu();
    const task = cpu.executable_tasks.dequeue();
    frame.* = task.registers;
    task.paging_context.apply();
    os.platform.set_current_task(task);
    task.platform_data.load_state();
}
