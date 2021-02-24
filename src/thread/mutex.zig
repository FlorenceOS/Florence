const os = @import("root").os;
const std = @import("std");

pub const Mutex = struct {
  held_by: ?*os.thread.Task = null,
  queue: os.thread.QueueBase = .{},
  spinlock: os.thread.Spinlock = .{},

  const Held = struct {
    mtx: *Mutex,

    pub fn release(self: *const @This()) void {
      self.mtx.unlock();
    }
  };

  pub fn acquire(self: *@This()) Held {
    self.lock();
    return .{.mtx = self};
  }

  pub fn lock(self: *@This()) void {
    const lock_state = self.spinlock.lock();
    if (self.held_by == null) {
      self.held_by = os.platform.get_current_task();
      self.spinlock.unlock(lock_state);
      return;
    }
    self.queue.add_back(os.platform.get_current_task());
    self.spinlock.ungrab();
    os.thread.scheduler.wait();
    os.platform.set_interrupts(lock_state);
  }

  fn unlock_impl(self: *@This()) void {
    @import("std").debug.assert(self.held_by_me());
    self.held_by = null;
  }

  pub fn unlock(self: *@This()) void {
    const lock_state = self.spinlock.lock();
    std.debug.assert(self.held_by_me());
    if (self.queue.remove_front()) |task| {
      self.held_by = task;
      os.thread.scheduler.wake(task);
    } else {
      self.held_by = null;
    }
    self.spinlock.unlock(lock_state);
  }

  pub fn held(self: *const @This()) bool {
    if(self.held_by) |h|
      return true;
    return false;
  }

  pub fn held_by_me(self: *const @This()) bool {
    return self.held_by == os.platform.get_current_task();
  }

  pub fn init(self: *@This()) void {
    self.queue.init();
  }
};
