pub const os = @import("root").os;

pub var bsp_task: os.thread.Task = .{};

const TPIDR_EL1 = os.platform.msr(*os.platform.smp.CoreData, "TPIDR_EL1");

pub const CoreData = struct {

};

pub const sched_stack_size = 0x10000;
pub const int_stack_size = 0x10000;
pub const task_stack_size = 0x10000;
pub const stack_guard_size = 0x1000;

pub fn get_current_cpu() *os.platform.smp.CoreData {
  return TPIDR_EL1.read();
}

pub fn set_current_cpu(ptr: *os.platform.smp.CoreData) void {
  TPIDR_EL1.write(ptr);
}

pub const TaskData = struct {
  stack: ?*[task_stack_size]u8 = null,
};

const task_stack_size = 1024 * 16;

pub fn yield() void {
  asm volatile("SVC #'Y'");
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
