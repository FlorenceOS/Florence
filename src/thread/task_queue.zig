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

  pub fn sleep(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    const state = os.platform.get_and_disable_interrupts();
    if(!@call(.{.modifier = .always_inline}, atomic_op, args)) {
      os.platform.set_interrupts(state);
      return false;
    }

    if(self.remove_front()) |next_task| {
      self.add_back(os.platform.get_current_task());
      os.platform.set_interrupts(state);
      os.platform.yield_to_task(next_task);
    } else {
      os.platform.set_interrupts(state);
    }

    return true;
  }

  pub fn init(self: *@This()) void {
    self.queue.init();
  }
};

pub const WaitQueue = struct {
  q: QueueBase = .{},
  lock: os.thread.Spinlock = .{},

  pub fn sleep(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    return self.q.sleep(atomic_op, args);
  }

  pub fn wake(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    const s = self.lock.lock();

    @call(.{.modifier = .always_inline}, atomic_op, args);

    if(self.q.remove_front()) |new_task| {
      // Enqueue the task into the ready queue
      os.thread.scheduler.ready.enqueue(new_task);
      return true;
    }
    self.lock.unlock(s);
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

  pub fn sleep(self: *@This(), comptime atomic_op: anytype, args: anytype) bool {
    return self.q.sleep(atomic_op, args);
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
