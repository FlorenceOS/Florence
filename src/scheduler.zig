const platform = @import("platform.zig");
const arch = @import("builtin").arch;
const vmm = @import("vmm.zig");
const log = @import("logger.zig").log;

const std = @import("std");

pub const Task = struct {
  registers: platform.InterruptFrame,
  platform_data: platform.TaskData,
  next_task: ?*Task,
};

// A simple lock which can be taken by any execution flow, across task switches.
pub const MultitaskingLock = struct {
  taken: bool = false,

  pub fn try_lock(self: *MultitaskingLock) bool {
    return !@atomicRmw(bool, &self.taken, .Xchg, true, .AcqRel);
  }

  pub fn lock(self: *MultitaskingLock) void {
    while(!self.try_lock()) { platform.spin_hint(); }
  }

  pub fn unlock(self: *MultitaskingLock) void {
    std.debug.assert(self.taken);
    @atomicStore(bool, &self.taken, false, .Release);
  }
};

// Lock something to a specific task
// Cannot be used by the scheduler as it might be switching tasks
// pub const Mutex = struct {
//   owner: ?*Task = null,

//   pub fn try_lock(self: *Mutex) bool {

//   }
// };

// Just a simple round robin implementation
const TaskQueue = struct {
  first_task: ?*Task = null,
  last_task: ?*Task = null,
  lock: MultitaskingLock = .{},

  pub fn choose_next_task(self: *@This()) *Task {
    self.lock.lock();
    defer self.lock.unlock();

    while(self.first_task == null) {
      platform.spin_hint();
    }

    const task = self.first_task.?;

    if(self.last_task == task) {
      self.last_task = null;
      self.first_task = null;
    }
    else {
      self.first_task = task.next_task;
    }

    task.next_task = null;
    return task;
  }

  pub fn enqueue_task_front(self: *@This(), task: *Task) void {
    self.lock.lock();
    defer self.lock.unlock();

    if(self.first_task) |ft| {
      task.next_task = ft;
    } else {
      self.last_task = task;
    }
    self.first_task = task;
  }

  pub fn enqueue_task(self: *@This(), task: *Task) void {
    self.lock.lock();
    defer self.lock.unlock();

    task.next_task = null;

    if(self.first_task == null)
      self.first_task = task;

    if(self.last_task) |*lt|
      lt.*.next_task = task;

    self.last_task = task;
  }
};

pub var queue = TaskQueue{};

fn switch_task(frame: *platform.InterruptFrame, next_task: *Task) void {
  platform.set_current_task(next_task);
  frame.* = next_task.registers;
}

// Yielding from a task
pub fn yield_handler(frame: *platform.InterruptFrame) void {
  platform.get_current_task().registers = frame.*;
  queue.enqueue_task(platform.get_current_task());
  switch_task(frame, queue.choose_next_task());
}

fn exit_impl() !void {
  const current_task = try platform.self_exited();
  try vmm.free_single(current_task);
}

// Exiting a task
pub fn exit_handler(frame: *platform.InterruptFrame) void {
  exit_impl() catch |err| {
    log("Could not exit task: {}\n", .{@errorName(err)});
    while(true) { }
  };
  switch_task(frame, queue.choose_next_task());
}

// Starting up a new processor
pub fn startup_handler(frame: *platform.InterruptFrame) void {
  const task = vmm.alloc_single(Task) catch |err| {
    log("Error while allocating task: {}\n", .{@errorName(err)});
    while(true) { }
  };

  task.platform_data = platform.TaskData{};

  platform.set_current_task(task);
}

// Creating a new task from an existing one
pub fn make_task(func: anytype, args: anytype) !void {
  const task = try vmm.alloc_single(Task);
  errdefer vmm.free_single(task) catch unreachable;
  try platform.new_task_call(task, func, args);
}

pub fn exit_task() noreturn {
  platform.exit_task();
}

pub fn yield() void {
  platform.yield();
}

pub fn loop() noreturn {
  while(true) {
    platform.yield();
  }
}
