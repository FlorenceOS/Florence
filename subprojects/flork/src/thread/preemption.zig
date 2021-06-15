usingnamespace @import("root").preamble;

/// Store state of the current thread
pub fn saveCurrentState(frame: *os.platform.InterruptFrame) void {
    const current_task = os.platform.get_current_task();
    current_task.registers = frame.*;
}

/// Load state of the task. In other words, prepare the core to run the task
fn loadState(frame: *os.platform.InterruptFrame, task: *os.thread.Task) void {
    const cpu = os.platform.thread.get_current_cpu();
    const current_task = os.platform.get_current_task();

    frame.* = task.registers;
    os.platform.set_current_task(task);
    if (current_task.paging_context != task.paging_context) {
        task.paging_context.apply();
    }

    task.platform_data.loadState();
}

/// Await for the next task to come to the core and yield to it
pub fn awaitForTaskAndYield(frame: *os.platform.InterruptFrame) void {
    const cpu = os.platform.thread.get_current_cpu();
    loadState(frame, cpu.executable_tasks.dequeue());
}

/// Yield to the next task or stay in the same task if there is no next task. Use in timers
pub fn yieldOrStay(frame: *os.platform.InterruptFrame) void {
    preserve_state(frame);
    const cpu = os.platform.thread.get_current_cpu();
    if (cpu.executable_tasks.tryDequeue()) |task| {
        loadState(frame, task);
    }
}
