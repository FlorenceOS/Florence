const std = @import("std");
const os = @import("root").os;

/// Allocator used to allocate memory for new tasks
const task_alloc = os.memory.vmm.backed(.Ephemeral);

/// Load balancer lock. Locked when scheduler finds the best CPU for the task
/// or when task terminates
var balancer_lock = os.thread.Spinlock{};

/// Move to the next task.
/// NOTE: Should be called in interrupt disabled context if its
/// not the last time task runs
pub fn wait() void {
    const wait_callback = struct {
        fn wait_callback(frame: *os.platform.InterruptFrame, _: usize) void {
            os.thread.preemption.store_current_state(frame);
            os.thread.preemption.await_task_and_yield(frame);
        }
    }.wait_callback;
    os.platform.sched_call(wait_callback, undefined);
}

/// Terminate current task to never run it again
pub fn leave() noreturn {
    wait();
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

/// Create a new task that calls a function with given arguments.
/// Uses heap, so don't create tasks in interrupt context
pub fn make_task(func: anytype, args: anytype) !*os.thread.Task {
    const task = try task_alloc.create(os.thread.Task);
    errdefer task_alloc.destroy(task);

    try task.allocate_stack();
    errdefer task.free_stack();

    task.paging_context = os.platform.get_current_task().paging_context;
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

    os.log("Task allocated to core {}\n", .{best_cpu_idx});

    errdefer {
        const state = balancer_lock.lock();
        os.platform.smp.cpus[best_cpu_idx].tasks_count -= 1;
        balancer_lock.unlock(state);
    }

    // Initialize task in a way that it will execute func with args on the startup
    const entry = os.thread.NewTaskEntry.alloc(task, func, args);
    try os.platform.thread.init_task_call(task, entry);
    return task;
}

/// Create and start a new task that calls a function with given arguments.
pub fn spawn_task(func: anytype, args: anytype) !void {
    const task = try make_task(func, args);
    os.platform.smp.cpus[task.allocated_core_id].executable_tasks.enqueue(task);
}

/// Exit current task
/// TODO: Should be reimplemented with URM
pub fn exit_task() noreturn {
    const task = os.platform.thread.self_exited();
    const id = if (task) |t| t.allocated_core_id else 0;

    const state = balancer_lock.lock();
    os.platform.smp.cpus[id].tasks_count -= 1;
    balancer_lock.unlock(state);

    if (task) |t| {
        task_alloc.destroy(t);
    }

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
