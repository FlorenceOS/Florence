const std = @import("std");
const os = @import("root").os;

const task_alloc = os.memory.vmm.backed(.Ephemeral);

// Creating a new task from an existing one
pub fn make_task(func: anytype, args: anytype) !void {
  const task = try task_alloc.create(os.thread.Task);
  errdefer task_alloc.destroy(task);
  try os.platform.new_task_call(task, func, args);
}

pub fn new_task() !*os.thread.Task {
  return task_alloc.create(os.thread.Task);
}

pub fn exit_task() noreturn {
  const task = os.platform.self_exited();
  if(task) |t|
    task_alloc.destroy(t);

  os.platform.get_current_cpu().executable_tasks.execute();
}

pub fn yield() void {
  // Always sleep in ready queue
  _ = os.platform.get_current_cpu().executable_tasks.sleep(
    struct {fn f() bool { return true; }}.f, .{});
}

pub fn init(task: *os.thread.Task) void {
  os.platform.set_current_task(task);
  os.platform.get_current_cpu().executable_tasks.init();
}
