const os = @import("root").os;
const std = @import("std");

const gdt = @import("gdt.zig");
const regs = @import("regs.zig");
const interrupts = @import("interrupts.zig");

pub var bsp_task: os.thread.Task = .{};

pub const kernel_gs_base = regs.MSR(u64, 0xC0000102);

pub fn set_current_cpu(cpu_ptr: *os.platform.smp.CoreData) void {
  kernel_gs_base.write(@ptrToInt(cpu_ptr));
}

pub fn get_current_cpu() *os.platform.smp.CoreData {
  return @intToPtr(*os.platform.smp.CoreData, kernel_gs_base.read());
}

pub fn self_exited() ?*os.thread.Task {
  const curr = os.platform.get_current_task();
  
  if(curr == &bsp_task)
    return null;

  if(curr.platform_data.stack != null) {
    // TODO: Add URM
  }
  return curr;
}

pub const TaskData = struct {
  stack: ?*[task_stack_size]u8 = null,
};

pub const CoreData = struct {
  gdt: gdt.Gdt = .{},
};

const task_stack_size = 1024 * 16;

const ephemeral = os.memory.vmm.backed(.Ephemeral);

pub fn new_task_call(new_task: *os.thread.Task, func: anytype, args: anytype) !void {
  const Args = @TypeOf(args);
  var had_error: u64 = undefined;
  var result: u64 = undefined;
 
  const cpu = &os.platform.smp.cpus[new_task.allocated_core_id];
 
  new_task.platform_data.stack = try ephemeral.create([task_stack_size]u8);
  errdefer ephemeral.destroy(new_task.platform_data.stack.?);
 
  const stack_bottom = @ptrToInt(new_task.platform_data.stack);
  var stack_top = stack_bottom + task_stack_size;
  const entry = os.thread.NewTaskEntry.alloc_on_stack(func, args, stack_top, stack_bottom);
  stack_top = os.lib.libalign.align_down(usize, 16, @ptrToInt(entry));

  new_task.registers.eflags = regs.eflags();
  new_task.registers.rdi = @ptrToInt(entry);
  new_task.registers.rsp = stack_top;
  new_task.registers.cs = gdt.selector.code64;
  new_task.registers.ss = gdt.selector.data64;
  new_task.registers.fs = gdt.selector.data64;
  new_task.registers.es = gdt.selector.data64;
  new_task.registers.gs = gdt.selector.data64;
  new_task.registers.ds = gdt.selector.data64;
  new_task.registers.rip = @ptrToInt(entry.function);
 
  os.platform.smp.cpus[new_task.allocated_core_id].executable_tasks.enqueue(new_task);
}

pub fn yield(enqueue: bool) void {
  asm volatile(
    \\int $0x6B
    :
    : [_] "{rbx}" (@boolToInt(enqueue))
    : "memory"
  );
}

pub fn yield_handler(frame: *interrupts.InterruptFrame) void {
  const current_task = os.platform.get_current_task();

  current_task.registers = frame.*;
  if (frame.rbx == 1) {
    os.platform.smp.cpus[current_task.allocated_core_id].executable_tasks.enqueue(current_task);
  }
  
  await_handler(frame);
}

pub fn await_handler(frame: *interrupts.InterruptFrame) void {
  const current_task = os.platform.get_current_task();
  const curent_context = current_task.paging_context;

  var next_task: *os.thread.Task = undefined;
  while (true) {
    next_task = os.platform.thread.get_current_cpu().executable_tasks.dequeue() orelse continue;
    break;
  }

  os.platform.set_current_task(next_task);
  next_task.paging_context.apply();
  frame.* = next_task.registers;
}
