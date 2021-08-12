usingnamespace @import("root").preamble;

/// Allocator used to allocate memory for new tasks
const task_alloc = os.memory.pmm.phys_heap;

/// Load balancer lock. Locked when scheduler finds the best CPU for the task
/// or when task terminates
var balancer_lock = os.thread.Spinlock{};

/// Move to the next task.
/// NOTE: Should be called in interrupt disabled context if its
/// not the last time task runs
pub fn wait() void {
    const waitCallback = struct {
        fn waitCallback(frame: *os.platform.InterruptFrame, _: usize) void {
            os.thread.preemption.saveCurrentState(frame);
            os.thread.preemption.awaitForTaskAndYield(frame);
        }
    }.waitCallback;
    os.platform.sched_call(waitCallback, undefined);
}

/// Equivalent to wait(), but allows to run custom callback on sched_stack.
/// If callback returns true, task should be suspended
pub fn waitWithCallback(params: struct { 
    callback: fn (*os.platform.InterruptFrame, usize) bool, 
    ctx: usize = undefined,
}) void {
    const ParamsType = @TypeOf(params);
    const paramsAddr = @ptrToInt(&params);
    const waitCallback = struct {
        fn waitCallback(frame: *os.platform.InterruptFrame, ctx: usize) void {
            const passed = @intToPtr(*ParamsType, ctx);

            os.thread.preemption.saveCurrentState(frame);
            if (!passed.callback(frame, passed.ctx)) {
                return;
            }

            os.thread.preemption.awaitForTaskAndYield(frame);
        }
    }.waitCallback;
    os.platform.sched_call(waitCallback, paramsAddr);
}

/// Sleep + release spinlock
pub fn waitReleaseSpinlock(spinlock: *os.thread.Spinlock) void {
    const callback = struct {
        fn callback(frame: *os.platform.InterruptFrame, ctx: usize) bool {
            const lock = @intToPtr(*os.thread.Spinlock, ctx);
            lock.ungrab();
            return true;
        }
    }.callback;
    waitWithCallback(.{.callback = callback, .ctx = @ptrToInt(spinlock)});
}

/// Terminate current task to never run it again
pub fn leave() noreturn {
    const leaveCallback = struct {
        fn leaveCallback(frame: *os.platform.InterruptFrame, _: usize) void {
            os.thread.preemption.awaitForTaskAndYield(frame);
        }
    }.leaveCallback;
    os.platform.sched_call(leaveCallback, undefined);
    unreachable;
}

/// Preempt to the next task
pub fn yield() void {
    const state = os.platform.get_and_disable_interrupts();
    os.platform.thread.get_current_cpu().executable_tasks.enqueue(os.platform.get_current_task());
    wait();
    os.platform.set_interrupts(state);
}

/// Wake a task that has called `wait`
pub fn wake(task: *os.thread.Task) void {
    os.platform.smp.cpus[task.allocated_core_id].executable_tasks.enqueue(task);
}

/// Initialize a task for usage, must call destroyTask to clean up
/// You still have to initialize:
///   * Paging context
///   * Register state
pub fn initTask(task: *os.thread.Task) !void {
    try task.allocStack();
    errdefer task.freeStack();

    // Find the best CPU for the task
    var best_cpu_idx: usize = 0;
    {
        const state = balancer_lock.lock();
        // TODO: maybe something more sophisticated?
        for (os.platform.smp.cpus) |*cpu, i| {
            if (cpu.tasks_count < os.platform.smp.cpus[best_cpu_idx].tasks_count) {
                best_cpu_idx = i;
            }
        }
        task.allocated_core_id = best_cpu_idx;
        os.platform.smp.cpus[best_cpu_idx].tasks_count += 1;
        balancer_lock.unlock(state);
    }
}

/// Creates a new task on the heap and calls initTask() on it
pub fn createTask() !*os.thread.Task {
    const task = try task_alloc.create(os.thread.Task);
    errdefer task_alloc.destroy(task);

    try initTask(task);

    return task;
}

/// Create and start a new kernel task that calls a function with given arguments.
/// Paging context is copied from the current one, task is automatically enqueued
pub fn spawnTask(func: anytype, args: anytype) !void {
    const task = try createTask();
    errdefer destroyTask(task);

    task.paging_context = os.platform.get_current_task().paging_context;

    // Initialize task in a way that it will execute func with args on the startup
    const entry = os.thread.NewTaskEntry.alloc(task, func, args);
    try os.platform.thread.init_task_call(task, entry);

    task.enqueue();
}

/// Effectively destroy a task (cleanup after initTask() or createTask())
pub fn destroyTask(task: ?*os.thread.Task) void {
    const id = if (task) |t| t.allocated_core_id else 0;

    const state = balancer_lock.lock();
    os.platform.smp.cpus[id].tasks_count -= 1;
    balancer_lock.unlock(state);

    if (task) |t| {
        task_alloc.destroy(t);
    }

    // TODO: Delete stacks in such a way that we can return from the current interrupt
    // in case it still is in use
}

/// Exit current task
/// TODO: Should be reimplemented with URM
pub fn exitTask() noreturn {
    destroyTask(os.platform.thread.self_exited());

    leave();
}

/// Initialize scheduler
pub fn init(task: *os.thread.Task) void {
    const bsp = &os.platform.smp.cpus[0];

    bsp.bootstrap_stacks();
    os.platform.bsp_pre_scheduler_init();
    os.platform.set_current_task(task);
    bsp.executable_tasks.init(bsp);
}
