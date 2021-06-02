const os = @import("root").os;
const atmcqueue = os.lib.atmcqueue;

/// Task queue is a generic helper for the queue of tasks (allows to enqueue/dequeue them)
/// It does no locking (though it disables interrupts) for its operations
pub const TaskQueue = struct {
  queue: atmcqueue.MPSCUnboundedQueue(os.thread.Task, "atmcqueue_hook") = .{},
  last_ack: usize = 0,
  last_triggered: usize = 0,

  /// Remove task that is queue head from the queue. Returns null if queue is "empty"
  pub fn dequeue(self: *@This()) ?*os.thread.Task {
    const state = os.platform.get_and_disable_interrupts();
    if (self.last_ack < @atomicLoad(usize, &self.last_triggered, .Acquire)) {
      while (true) {
        os.platform.spin_hint();
        const note = self.queue.dequeue() orelse continue;
        self.last_ack += 1;
        os.platform.set_interrupts(state);
        return note;
      }
    }
    os.platform.set_interrupts(state);
    return null;
  }

  /// Enqueue task in the end of the queue.
  pub fn enqueue(self: *@This(), t: *os.thread.Task) void {
    const state = os.platform.get_and_disable_interrupts();
    _ = @atomicRmw(usize, &self.last_triggered, .Add, 1, .AcqRel);
    self.queue.enqueue(t);
    os.platform.set_interrupts(state);
  }
};

/// ReadyQueue is a data structure that implements core ready task queue logic
/// os.platform.thread.CoreData should define:
/// 1) start_monitoring: Initialize monitor to get ring events. If events occurs after this function 
/// call, it should be captured. Corresponds to MONITOR on x86
/// 2) wait: Wait for events. If one was recieved after call to start_monitoring, return
/// immediatelly
pub const ReadyQueue = struct {
  queue: TaskQueue = .{},
  cpu: *os.platform.smp.CoreData = undefined,

  /// Enqueue task to run
  pub fn enqueue(self: *@This(), task: *os.thread.Task) void {
    self.queue.enqueue(task);
    self.cpu.platform_data.ring();
  }

  /// Dequeue task. Waits for one to become available
  /// Should run in interrupts enabled context
  pub fn dequeue(self: *@This()) *os.thread.Task {
    while (true) {
      // Begin waiting for ring events
      self.cpu.platform_data.start_monitoring();
      // If task already there, just return
      if (self.queue.dequeue()) |task| {
        return task;
      }
      // Wait for events
      self.cpu.platform_data.wait();
    }
  }
  
  /// Try to dequeue task
  pub fn try_dequeue(self: *@This()) ?*os.thread.Task {
    return self.queue.dequeue();
  }

  /// Initialize atomic queue used to store tasks
  pub fn init(self: *@This(), cpu: *os.platform.smp.CoreData) void {
    self.cpu = cpu;
  }
};
