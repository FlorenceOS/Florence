const os = @import("root").os;

pub const Mutex = struct {
  held_by: ?*os.thread.Task = null,
  queue: os.thread.WaitQueue = .{},

  fn lock_impl(self: *@This()) bool {
    if(self.held())
      return false;
    self.held_by = os.platform.get_current_task();
    return true;
  }

  pub fn lock(self: *@This()) void {
    while(!self.queue.sleep(lock_impl, .{self})) {

    }
  }

  fn unlock_impl(self: *@This()) void {
    @import("std").debug.assert(self.held_by_me());
    self.held_by = null;
  }

  pub fn unlock(self: *@This()) void {
    _ = self.queue.wake(unlock_impl, .{self});
  }

  pub fn held(self: *const @This()) bool {
    if(self.held_by) |h|
      return true;
    return false;
  }

  pub fn held_by_me(self: *const @This()) bool {
    return self.held_by == os.platform.get_current_task();
  }
};
