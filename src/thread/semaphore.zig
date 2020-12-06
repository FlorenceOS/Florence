const os = @import("root").os;

pub const Semaphore = struct {
  counter: usize,
  queue: os.thread.TaskQueue = .{},

  fn P_impl(self: *@This(), bp: *bool) bool {
    const b = self.counter == 0;
    if(!b) {
      self.counter -= 1;
    }
    bp.* = b;
    return b;
  }

  pub fn P(self: *@This()) void {
    var b: bool = true;

    while(b) {
      queue.sleep(P_impl, .{self, &b});
    }
  }

  fn V_impl(self: *@This()) void {
    self.counter += 1;
  }

  pub fn V(self: *@This()) void {
    queue.wake(V_impl, .{self});
  }
};
