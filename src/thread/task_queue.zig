const os = @import("root").os;
const atmcqueue = os.lib.atmcqueue;

const QueueBase = struct {
  queue: atmcqueue.MPSCUnboundedQueue(os.thread.Task, "atmcqueue_hook") = undefined,
  last_ack: usize = 0,
  last_triggered: usize = 0,

  fn remove_front(self: *@This()) ?*os.thread.Task {
    const state = os.platform.get_and_disable_interrupts();
    if (self.last_ack < @atomicLoad(usize, &self.last_triggered, .Acquire)) {
      while (true) {
        const note = self.queue.dequeue() orelse continue;
        self.last_ack += 1;
        os.platform.set_interrupts(state);
        return note;
      }
    }
    os.platform.set_interrupts(state);
    return null;
  }

  fn add_back(self: *@This(), t: *os.thread.Task) void {
    const state = os.platform.get_and_disable_interrupts();
    _ = @atomicRmw(usize, &self.last_triggered, .Add, 1, .AcqRel);
    self.queue.enqueue(t);
    os.platform.set_interrupts(state);
  }

  pub fn init(self: *@This()) void {
    self.queue.init();
  }
};

pub const WaitQueue = struct {
  q: QueueBase = .{},
  lock: os.thread.Spinlock = .{},

  pub fn sleep(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    const state = self.lock.lock();

    if(!@call(.{.modifier = .always_inline}, atomic_op, args)) {
      self.lock.unlock(state);
      return false;
    }

    if(self.q.remove_front()) |next_task| {
      self.q.add_back(os.platform.get_current_task());
      self.lock.unlock(state);
      os.platform.yield_to_task(next_task);
    } else {
      self.lock.unlock(state);
    }

    return true;
  }

  pub fn wake(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    const s = self.lock.lock();
    defer self.lock.unlock(s);

    @call(.{.modifier = .always_inline}, atomic_op, args);

    if(self.q.remove_front()) |new_task| {
      // Enqueue the task into the ready queue
      os.platform.get_current_cpu().executable_tasks.enqueue(new_task);
      return true;
    }
    return false;
  }

  pub fn wake_all(self: *@This()) void {
    while(self.wake(struct {fn f() void {}}.f, .{})) { }
  }

  pub fn init(self: *@This()) void {
    self.q.init();
  }
};

pub const ReadyQueue = struct {
  q: QueueBase = .{},

  fn fetch_next(self: *@This()) ?*os.thread.Task {
    const state = os.platform.get_and_disable_interrupts();
    defer os.platform.set_interrupts(state);
    return self.q.remove_front();
  }

  pub fn sleep(self: *@This(), comptime atomic_op: anytype, args: anytype) void {
    if(self.fetch_next()) |next_task| {
      self.q.add_back(os.platform.get_current_task());
      os.platform.yield_to_task(next_task);
    }
  }

  pub fn execute(self: *@This()) noreturn {
    while(true) {
      if(self.q.remove_front()) |new_task| {
        // We will never return from this since we
        // didn't enqueue ourselves anywhere else
        os.platform.yield_to_task(new_task);
        unreachable;
      }
      // TODO: wait for interrupt
    }
  }

  pub fn enqueue(self: *@This(), t: *os.thread.Task) void {
    self.q.add_back(t);
  }

  pub fn init(self: *@This()) void {
    self.q.init();
  }
};
