const std = @import("std");
const os = @import("root").os;

const task_alloc = os.memory.vmm.backed(.Ephemeral);

pub var ready = os.thread.ReadyQueue{};

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
  const task = try os.platform.self_exited();
  if(task) |t|
    task_alloc.destroy(t);

  ready.execute();
}

pub fn yield() void {
  // Always sleep in ready queue
  _ = ready.sleep(struct {fn f() bool { return true; }}.f, .{});
}
