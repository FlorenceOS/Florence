const os = @import("root").os;
const atmcqueue = os.lib.atmcqueue;

/// Task queue is a generic helper for the queue of tasks (allows to enqueue/dequeue them)
/// It does no locking (though it disables interrupts) for its operations
pub const TaskQueue = struct {
  queue: atmcqueue.MPSCUnboundedQueue(os.thread.Task, "atmcqueue_hook") = undefined,
  last_ack: usize = 0,
  last_triggered: usize = 0,

  /// Spin until new events are available
  /// Used only if Doorbell is not implemented for the given arch
  fn wait(self: *@This()) void {
    while (self.last_ack == @atomicLoad(usize, &self.last_triggered, .Acquire)) {
      os.platform.spin_hint();
    }
  }

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

  /// Initialize atomic queue used to store tasks
  pub fn init(self: *@This()) void {
    self.queue.init();
  }
};

/// True if CoreDoorbell is implemented
const use_doorbell = @hasDecl(os.platform.thread, "CoreDoorbell");

/// ReadyQueue is a data structure that implements core ready task queue logic
/// With the help of os.platform.thread.CoreDoorbell to notify about newer tasks
/// os.platform.thread.CoreDoorbell should define:
/// 1) start_monitoring: Initialize monitor to get ring events. If events occurs after  this function call,
/// it should be captured. Corresponds to MONITOR on x86
/// 2) wait: Wait for events. If one was recieved after call to start_monitoring, return immediatelly
pub const ReadyQueue = struct {
  queue: TaskQueue = .{},
  doorbell: if (use_doorbell) os.platform.thread.CoreDoorbell else void = .{},

  /// Enqueue task to run
  pub fn enqueue(self: *@This(), task: *os.thread.Task) void {
    self.queue.enqueue(task);
    if (use_doorbell) {
      self.doorbell.ring();
    }
  }

  /// Dequeue task. Waits for one to become available
  /// Should run in interrupts enabled context
  pub fn dequeue(self: *@This()) *os.thread.Task {
    while (true) {
      // Begin waiting for ring events
      if (use_doorbell) {
        self.doorbell.start_monitoring();
      }
      // If task already there, just return
      if (self.queue.dequeue()) |task| {
        return task;
      }
      // Wait for events
      if (use_doorbell) {
        self.doorbell.wait();
      } else {
        self.queue.wait();
      }
    }
  }
  
  /// Try to dequeue task
  pub fn try_dequeue(self: *@This()) ?*os.thread.Task {
    return self.queue.dequeue();
  }

  /// Initialize atomic queue used to store tasks
  pub fn init(self: *@This()) void {
    if (use_doorbell) {
      self.doorbell.init();
    }
    self.queue.init();
  }
};
