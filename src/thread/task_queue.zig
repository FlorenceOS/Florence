const os = @import("root").os;
const atmcqueue = os.lib.atmcqueue;

pub const TaskQueue = struct {
  queue: atmcqueue.MPSCUnboundedQueue(os.thread.Task, "atmcqueue_hook") = undefined,
  last_ack: usize = 0,
  last_triggered: usize = 0,

  pub fn dequeue(self: *@This()) ?*os.thread.Task {
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

  pub fn enqueue(self: *@This(), t: *os.thread.Task) void {
    const state = os.platform.get_and_disable_interrupts();
    _ = @atomicRmw(usize, &self.last_triggered, .Add, 1, .AcqRel);
    self.queue.enqueue(t);
    os.platform.set_interrupts(state);
  }

  pub fn init(self: *@This()) void {
    self.queue.init();
  }
};
