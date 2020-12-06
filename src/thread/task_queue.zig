const os = @import("root").os;

// Just a simple round robin implementation
pub const TaskQueue = struct {
  first_task: ?*os.thread.Task = null,
  last_task: ?*os.thread.Task = null,
  lock: @import("spinlock.zig").Spinlock = .{},

  fn remove_front(self: *@This()) ?*os.thread.Task {
    if(self.first_task) |task| {
      if(self.last_task == task) {
        self.last_task = null;
        self.first_task = null;  
      } else {
        self.first_task = task.next_task;
      }

      return task;
    }
    return null;
  }

  fn add_back(self: *@This(), t: *os.thread.Task) void {
    if(self.last_task) |ltask| {
      ltask.next_task = t;
    } else {
      self.first_task = t;
    }
    self.last_task = t;
  }

  pub fn enqueue(self: *@This(), t: *os.thread.Task) void {
    const s = self.lock.lock();
    defer self.lock.unlock(s);

    self.add_back(t);
  }

  pub fn sleep(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    const s = self.lock.lock();

    if(!@call(.{.modifier = .always_inline}, atomic_op, args))
      return false;

    if(self.remove_front()) |next_task| {
      self.add_back(os.platform.get_current_task());
      self.lock.unlock(s);
      os.platform.yield_to_task(next_task);
    } else {
      self.lock.unlock(s);
    }

    return true;
  }

  pub fn wake(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    const s = self.lock.lock();

    @call(.{.modifier = .always_inline}, atomic_op, args);

    if(self.remove_front()) |new_task| {
      const curr_task = os.platform.get_current_task();
      if(self == &os.thread.scheduler.ready) {
        self.add_back(curr_task);
      } else {
        os.thread.scheduler.ready.enqueue(curr_task);
      }
      self.lock.unlock(s);
      os.platform.yield_to_task(new_task);
      return true;
    }
    self.lock.unlock(s);
    return false;
  }

  pub fn wake_all(self: *@This()) void {
    while(self.wake(struct {fn f() void {}}.f, .{})) { }
  }

  pub fn execute(self: *@This()) noreturn {
    const s = self.lock.lock();

    while(true) {
      if(self.remove_front()) |new_task| {
        // Just let go of the lock when we eventually find a
        // task to run
        self.lock.unlock(s);

        // We will never return from this since we
        // didn't enqueue ourselves anywhere else
        os.platform.yield_to_task(new_task);
        unreachable;
      }

      // If we couldn't find a task to enter, await an interrupt
      // while not holding the lock
      self.lock.ungrab();
      os.platform.await_interrupt();
      self.lock.grab();
    }
  }
};
