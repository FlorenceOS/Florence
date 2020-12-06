const std = @import("std");
const os = @import("root").os;

pub var ready = os.thread.TaskQueue{};

fn exit_impl() !void {
  const task = try os.platform.self_exited();
  if(task) |t|
    os.memory.vmm.ephemeral.destroy(t);
}

// Exiting a task
pub fn exit_handler(frame: *os.platform.InterruptFrame) void {
  exit_impl() catch |err| {
    os.log("Could not exit task: {}\n", .{@errorName(err)});
    @panic("");
  };

  ready.execute();
}

// Creating a new task from an existing one
pub fn make_task(func: anytype, args: anytype) !void {
  const task = try os.memory.vmm.ephemeral.create(os.thread.Task);
  errdefer os.memory.vmm.ephemeral.destroy(task);
  try os.platform.new_task_call(task, func, args);
}

pub fn exit_task() noreturn {
  os.platform.exit_task();
}

pub fn yield() void {
  // Always sleep in ready queue
  _ = ready.sleep(struct {fn f() bool { return true; }}.f, .{});
}
