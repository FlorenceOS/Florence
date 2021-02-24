const os = @import("root").os;
const atmcqueue = os.lib.atmcqueue;

pub const QueueBase = struct {
  queue: atmcqueue.MPSCUnboundedQueue(os.thread.Task, "atmcqueue_hook") = undefined,
  last_ack: usize = 0,
  last_triggered: usize = 0,

  pub fn remove_front(self: *@This()) ?*os.thread.Task {
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

  pub fn add_back(self: *@This(), t: *os.thread.Task) void {
    const state = os.platform.get_and_disable_interrupts();
    _ = @atomicRmw(usize, &self.last_triggered, .Add, 1, .AcqRel);
    self.queue.enqueue(t);
    os.platform.set_interrupts(state);
  }

  pub fn init(self: *@This()) void {
    self.queue.init();
  }
};

pub const ReadyQueue = struct {
  q: QueueBase = .{},

  /// Get next task to run
  pub fn dequeue(self: *@This()) ?*os.thread.Task {
    return self.q.remove_front();
  }

  /// Go to sleep without the hope of someone waking as up
  pub fn leave(self: *@This()) noreturn {
    os.platform.yield(false);
    unreachable;
  }

  pub fn enqueue(self: *@This(), t: *os.thread.Task) void {
    self.q.add_back(t);
  }

  pub fn init(self: *@This()) void {
    self.q.init();
  }
};
