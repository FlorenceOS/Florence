const std = @import("std");
const os = @import("root").os;

pub fn wait() void {
  os.platform.thread.yield();
}

pub fn leave() noreturn {
  wait();
  unreachable;
}

pub fn yield() void {
  const state = os.platform.get_and_disable_interrupts();
  os.platform.thread.get_current_cpu().executable_tasks.enqueue(os.platform.get_current_task());
  os.platform.thread.yield();
  os.platform.set_interrupts(state);
}

pub fn wake(task: *os.thread.Task) void {
  os.platform.smp.cpus[task.allocated_core_id].executable_tasks.enqueue(task);
}

const task_alloc = os.memory.vmm.backed(.Ephemeral);
var balancer_lock = os.thread.Spinlock{};

/// Allocating memory for the new task
pub fn new_task() !*os.thread.Task {
  return task_alloc.create(os.thread.Task);
}

/// Creating a new task that calls a function. Should be called
/// from an existing task, e.g can't be called from an interrupt context
pub fn make_task(func: anytype, args: anytype) !void {
  const task = try new_task();
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

  errdefer {
    const state = balancer_lock.lock();
    os.platform.smp.cpus[best_cpu_idx].tasks_count -= 1;
    balancer_lock.unlock(state);
  }

  errdefer task_alloc.destroy(task);
  try os.platform.thread.new_task_call(task, func, args);
}

pub fn exit_task() noreturn {
  const task = os.platform.thread.self_exited();
  const id = if (task) |t| t.allocated_core_id else 0;

  const state = balancer_lock.lock();
  os.platform.smp.cpus[id].tasks_count -= 1;
  balancer_lock.unlock(state);

  if(task) |t|
    task_alloc.destroy(t);

  leave();
}

pub fn init(task: *os.thread.Task) void {
  os.platform.set_current_task(task);
  os.platform.thread.get_current_cpu().executable_tasks.init();
}
