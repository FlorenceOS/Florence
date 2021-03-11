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
  pub fn load_state(self: *@This()) void { }
};

pub fn yield() void {
  asm volatile("SVC #'Y'");
}

pub fn set_interrupt_stack(int_stack: usize) void {
  os.log("Setting the interrupt stack to 0x{X}\n", .{int_stack});

  asm volatile(
    \\ MSR SPSel, #1
    \\ MOV SP, %[int_stack]
    \\ MSR SPSel, #0
    :
    : [int_stack] "r" (int_stack)
  );
}

pub fn init_task_call(new_task: *os.thread.Task, entry: *os.thread.NewTaskEntry) !void {
  const cpu = os.platform.thread.get_current_cpu();

  new_task.registers.pc = @ptrToInt(entry.function);
  new_task.registers.x0 = @ptrToInt(entry);
  new_task.registers.sp = os.lib.libalign.align_down(usize, 16, @ptrToInt(entry));

  set_interrupt_stack(cpu.int_stack);
}

pub fn self_exited() ?*os.thread.Task {
  const curr = os.platform.get_current_task();
  
  if(curr == &bsp_task)
    return null;

  return curr;
}
