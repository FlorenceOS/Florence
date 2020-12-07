const std = @import("std");
const os = @import("root").os;

pub var ready = os.thread.TaskQueue{};

// Creating a new task from an existing one
pub fn make_task(func: anytype, args: anytype) !void {
  const task = try os.memory.vmm.ephemeral.create(os.thread.Task);
  errdefer os.memory.vmm.ephemeral.destroy(task);
  try os.platform.new_task_call(task, func, args);
}

pub fn exit_task() noreturn {
  const task = try os.platform.self_exited();
  if(task) |t|
    os.memory.vmm.ephemeral.destroy(t);

  ready.execute();
}

pub fn yield() void {
  // Always sleep in ready queue
  _ = ready.sleep(struct {fn f() bool { return true; }}.f, .{});
}
