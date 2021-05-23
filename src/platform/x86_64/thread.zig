const os = @import("root").os;
const std = @import("std");

const gdt = @import("gdt.zig");
const regs = @import("regs.zig");
const interrupts = @import("interrupts.zig");
const apic = @import("apic.zig");
const Tss = @import("tss.zig").Tss;

pub const sched_stack_size = 0x10000;
pub const int_stack_size = 0x10000;
pub const task_stack_size = 0x10000;
pub const stack_guard_size = 0x1000;
pub const ap_init_stack_size = 0x10000;

pub var bsp_task: os.thread.Task = .{};

pub const kernel_gs_base = regs.MSR(u64, 0xC0000102);

pub const TaskData = struct {
  tss: *Tss = undefined,
  
  pub fn load_state(self: *@This()) void {
    const cpu = os.platform.thread.get_current_cpu();

    self.tss.set_interrupt_stack(cpu.int_stack);
    self.tss.set_scheduler_stack(cpu.sched_stack);

    cpu.platform_data.gdt.update_tss(self.tss);
  }
};

pub const CoreData = struct {
  gdt: gdt.Gdt = .{},
  shared_tss: Tss = .{},
  shared_tss_loaded: bool = true,
  rsp_stash: u64 = undefined, // Stash for rsp after syscall instruction
  lapic: ?os.platform.phys_ptr(*volatile [0x100]u32) = undefined,
  lapic_id: u32 = 0,
};

pub const CoreDoorbell = struct {
  cpu: *os.platform.smp.CoreData,
  wakeable: bool,

  pub fn init(self: *@This(), cpu: *os.platform.smp.CoreData) void {
    self.cpu = cpu;
    self.wakeable = false;
  }

  pub fn ring(self: *@This()) void {
    const current_cpu = os.platform.thread.get_current_cpu();
    if (current_cpu.platform_data.lapic_id == self.cpu.platform_data.lapic_id) {
      return;
    }
    if (@atomicLoad(bool, &self.wakeable, .Acquire)) {
      apic.ipi(self.cpu.platform_data.lapic_id, interrupts.ring_vector);
    }
  }

  pub fn start_monitoring(self: *@This()) void {
    @atomicStore(bool, &self.wakeable, true, .Release);
  }

  pub fn wait(self: *@This()) void {
    asm volatile("sti; hlt; cli");
    @atomicStore(bool, &self.wakeable, false, .Release);
  }
};

const ephemeral = os.memory.vmm.backed(.Ephemeral);

pub fn init_task_call(new_task: *os.thread.Task, entry: *os.thread.NewTaskEntry) !void {
  const cpu = os.platform.thread.get_current_cpu();

  new_task.registers.eflags = regs.eflags();
  new_task.registers.rdi = @ptrToInt(entry);
  new_task.registers.rsp = os.lib.libalign.align_down(usize, 16, @ptrToInt(entry));
  new_task.registers.cs = gdt.selector.code64;
  new_task.registers.ss = gdt.selector.data64;
  new_task.registers.es = gdt.selector.data64;
  new_task.registers.ds = gdt.selector.data64;
  new_task.registers.rip = @ptrToInt(entry.function);

  const tss = try os.memory.vmm.backed(.Ephemeral).create(Tss);
  tss.* = .{};

  new_task.platform_data.tss = tss;
  tss.set_syscall_stack(new_task.stack);
}

pub fn sched_call_impl(fun: usize, ctx: usize) void {
  asm volatile(
    \\int %[sched_call_vector]
    :
    : [sched_call_vector] "i" (interrupts.sched_call_vector),
      [_]"{rdi}"(fun),
      [_]"{rsi}"(ctx),
  );
}

pub fn sched_call_impl_handler(frame: *os.platform.InterruptFrame) void {
  const fun: fn (*os.platform.InterruptFrame, usize) void = @intToPtr(fn (*os.platform.InterruptFrame, usize) void, frame.rdi);
  const ctx: usize = frame.rsi;
  fun(frame, ctx);
}

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
