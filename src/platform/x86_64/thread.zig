const os = @import("root").os;
const std = @import("std");

const gdt = @import("gdt.zig");
const regs = @import("regs.zig");
const interrupts = @import("interrupts.zig");
const Tss = @import("tss.zig").Tss;

pub const sched_stack_size = 0x10000;
pub const int_stack_size = 0x10000;
pub const task_stack_size = 0x10000;
pub const stack_guard_size = 0x1000;

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
  rsp_stash: u64 = undefined, // Stash for rsp after syscall instruction
  lapic: ?os.platform.phys_ptr(*volatile [0x100]u32) = undefined,
};

pub const CoreDoorbell = struct {
  addr: *usize = undefined,

  pub fn init(self: *@This()) void {
    const nonbacked = os.memory.vmm.nonbacked();

    const virt = @ptrToInt(os.vital(nonbacked.allocFn(nonbacked, 4096, 1, 1, 0), "CoreDoorbell nonbacked").ptr);
    os.vital(os.memory.paging.map(.{
      .virt = virt,
      .size = 4096,
      .perm = os.memory.paging.rw(),
      .memtype = .MemoryWriteBack
    }), "CoreDoorbell map");

    self.addr = @intToPtr(*usize, virt);
  }

  pub fn ring(self: *@This()) void {
    @atomicStore(usize, self.addr, 0, .Release);
  }

  pub fn start_monitoring(self: *@This()) void {
    //asm volatile(
    //  "monitor"
    //  :
    //  : [_]"{rax}"(@ptrToInt(self.addr)),
    //    [_]"{ecx}"(@as(u32, 0)),
    //    [_]"{edx}"(@as(u32, 0)),
    //);
  }

  pub fn wait(self: *@This()) void {
    //asm volatile(
    //  \\sti
    //  \\mwait
    //  \\cli
    //  :
    //  : [_]"{eax}"(@as(u32, 0)),
    //    [_]"{ecx}"(@as(u32, 0))
    //);
    asm volatile("sti; nop; pause; cli");
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
