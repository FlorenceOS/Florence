pub const os = @import("root").os;

pub var bsp_task: os.thread.Task = .{};

pub const TaskData = struct {
  stack: ?*[task_stack_size]u8 = null,
};

const task_stack_size = 1024 * 16;

pub fn yield(should_enqueue: bool) void {
  asm volatile("SVC #'Y'" :: [_] "{x0}" (@boolToInt(should_enqueue)));
}

pub fn new_task_call(new_task: *os.thread.Task, func: anytype, args: anytype) !void {
  @panic("yield");
}

pub fn self_exited() ?*os.thread.Task {
  const curr = os.platform.get_current_task();
  
  if(curr == &bsp_task)
    return null;

  if(curr.platform_data.stack != null) {
    // TODO: Figure out how to free the stack while returning using it??
    // We can just leak it for now
    //try vmm.free_single(curr.platform_data.stack.?);
  }
  return curr;
}
