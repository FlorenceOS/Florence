const os = @import("root").os;
const std = @import("std");

const gdt = @import("gdt.zig");
const regs = @import("regs.zig");
const interrupts = @import("interrupts.zig");

pub const sched_stack_size = 0x10000;
pub const int_stack_size = 0x10000;
pub const task_stack_size = 0x10000;
pub const stack_guard_size = 0x1000;

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

  return curr;
}

pub const TaskData = struct {
};

pub const CoreData = struct {
  gdt: gdt.Gdt = .{},
};

const ephemeral = os.memory.vmm.backed(.Ephemeral);

pub fn new_task_call(new_task: *os.thread.Task, func: anytype, args: anytype) !void {
  const entry = os.thread.NewTaskEntry.alloc(new_task, func, args);

  new_task.registers.eflags = regs.eflags();
  new_task.registers.rdi = @ptrToInt(entry);
  new_task.registers.rsp = os.lib.libalign.align_down(usize, 16, @ptrToInt(entry));
  new_task.registers.cs = gdt.selector.code64;
  new_task.registers.ss = gdt.selector.data64;
  new_task.registers.fs = gdt.selector.data64;
  new_task.registers.es = gdt.selector.data64;
  new_task.registers.gs = gdt.selector.data64;
  new_task.registers.ds = gdt.selector.data64;
  new_task.registers.rip = @ptrToInt(entry.function);

  os.platform.smp.cpus[new_task.allocated_core_id].executable_tasks.enqueue(new_task);
}

pub fn yield() void {
  asm volatile("int $0x6B");
}

pub fn yield_handler(frame: *interrupts.InterruptFrame) void {
  const current_task = os.platform.get_current_task();
  const curent_context = current_task.paging_context;
  current_task.registers = frame.*;

  const next_task = switch_task(frame);
  if (current_task.paging_context != next_task.paging_context) {
    next_task.paging_context.apply();
  }
}

fn switch_task(frame: *interrupts.InterruptFrame) *os.thread.Task {
  var next_task: *os.thread.Task = undefined;
  while (true) {
    next_task = os.platform.thread.get_current_cpu().executable_tasks.dequeue() orelse continue;
    break;
  }

  os.platform.set_current_task(next_task);
  frame.* = next_task.registers;
  return next_task;
}

pub fn await_handler(frame: *interrupts.InterruptFrame) void {
  const next_task = switch_task(frame);
  next_task.paging_context.apply();
}
