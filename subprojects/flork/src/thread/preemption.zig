usingnamespace @import("root").preamble;

/// Store state of the current thread
pub fn store_current_state(frame: *os.platform.InterruptFrame) void {
    const current_task = os.platform.get_current_task();
    current_task.registers = frame.*;
}

/// Load state of the task. In other words, prepare the core to run the task
fn load_state(frame: *os.platform.InterruptFrame, task: *os.thread.Task) void {
    const cpu = os.platform.thread.get_current_cpu();
    const current_task = os.platform.get_current_task();

    frame.* = task.registers;
    os.platform.set_current_task(task);
    if (current_task.paging_context != task.paging_context) {
        task.paging_context.apply();
    }

    task.platform_data.load_state();
}

/// Await for the next task to come to the core and yield to it
pub fn await_task_and_yield(frame: *os.platform.InterruptFrame) void {
    const cpu = os.platform.thread.get_current_cpu();
    load_state(frame, cpu.executable_tasks.dequeue());
}

/// Yield to the next task or stay in the same task
/// if there is no next task. Use in timers
pub fn yield_or_not(frame: *os.platform.InterruptFrame) void {
    preserve_state(frame);
    const cpu = os.platform.thread.get_current_cpu();
    if (cpu.executable_tasks.try_dequeue()) |task| {
        load_state(frame, task);
    }
}
