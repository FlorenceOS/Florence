const os = @import("root").os;

const QueueBase = struct {
  first_task: ?*os.thread.Task = null,
  last_task: ?*os.thread.Task = null,
  lock: os.thread.Spinlock = .{},

  // Not thread safe!
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

  // Not thread safe!
  fn add_back(self: *@This(), t: *os.thread.Task) void {
    if(self.last_task) |ltask| {
      ltask.next_task = t;
    } else {
      self.first_task = t;
    }
    self.last_task = t;
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

};

pub const WaitQueue = struct {
  q: QueueBase = .{},

  pub fn sleep(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    return self.q.sleep(atomic_op, args);
  }

  pub fn wake(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    const s = self.q.lock.lock();

    @call(.{.modifier = .always_inline}, atomic_op, args);

    if(self.q.remove_front()) |new_task| {
      // Enqueue the task into the ready queue
      os.thread.scheduler.ready.enqueue(new_task);
      return true;
    }
    self.q.lock.unlock(s);
    return false;
  }

  pub fn wake_all(self: *@This()) void {
    while(self.wake(struct {fn f() void {}}.f, .{})) { }
  }
};

pub const ReadyQueue = struct {
  q: QueueBase = .{},

  pub fn sleep(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    return self.q.sleep(atomic_op, args);
  }

  pub fn execute(self: *@This()) noreturn {
    const s = self.q.lock.lock();
    while(true) {
      if(self.q.remove_front()) |new_task| {
        // Just let go of the lock when we eventually find a
        // task to run
        self.q.lock.unlock(s);

        // We will never return from this since we
        // didn't enqueue ourselves anywhere else
        os.platform.yield_to_task(new_task);
        unreachable;
      }

      // If we couldn't find a task to enter, await an interrupt
      // while not holding the lock
      self.q.lock.ungrab();
      os.platform.await_interrupt();
      self.q.lock.grab();
    }
  }

  pub fn enqueue(self: *@This(), t: *os.thread.Task) void {
    const s = self.q.lock.lock();
    defer self.q.lock.unlock(s);
    
    self.q.add_back(t);
  }
};
