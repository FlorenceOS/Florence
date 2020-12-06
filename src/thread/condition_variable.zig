const TaskQueue = @import("task_queue.zig").TaskQueue;

pub const ConditionVariable = struct {
  queue: TaskQueue = .{},

  fn wait_impl(mtx: anytype) bool {
    mtx.unlock();
  }

  pub fn wait(self: @This(), mtx: anytype) void {
    queue.sleep(wait_impl, .{mtx});
    mtx.lock();
  }

  pub fn signal(self: @This()) void {
    queue.wake();
  }

  pub fn broadcast(self: @This()) void {
    queue.wake_all();
  }
};
