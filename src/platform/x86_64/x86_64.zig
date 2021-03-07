const os = @import("root").os;
const std = @import("std");

const interrupts = @import("interrupts.zig");
const gdt = @import("gdt.zig");
const serial = @import("serial.zig");
const ports = @import("ports.zig");
const regs = @import("regs.zig");
const apic = @import("apic.zig");
const pci = os.platform.pci;

pub const paging = @import("paging.zig");
pub const pci_space = @import("pci_space.zig");
pub const thread = @import("thread.zig");
pub const PagingRoot = u64;
pub const InterruptFrame = interrupts.InterruptFrame;
pub const InterruptState = interrupts.InterruptState;

pub const irq_eoi = apic.eoi; 

pub fn get_and_disable_interrupts() InterruptState {
  return regs.eflags() & 0x200 == 0x200;
}

pub fn set_interrupts(s: InterruptState) void {
  if(s) {
    asm volatile(
      \\sti
    );
  } else {
    asm volatile(
      \\cli
    );
  }
}

pub fn platform_init() !void {
  try os.platform.acpi.init_acpi();
  apic.enable();
  set_interrupts(true);
  try os.platform.pci.init_pci();
}

pub fn platform_early_init() void {
  os.platform.smp.prepare();
  os.thread.scheduler.init(&thread.bsp_task);
  serial.init();
  try interrupts.init_interrupts();
  os.platform.smp.cpus[0].platform_data.gdt.load();
  os.memory.paging.init();
}

pub fn ap_init() void {
  os.memory.paging.kernel_context.apply();
  try interrupts.init_interrupts();

  const cpu = os.platform.thread.get_current_cpu();
  cpu.platform_data.gdt.load();

  asm volatile(
    \\mov %[stack], %%rsp
    \\jmp *%[dest]
    :
    : [stack] "rm" (cpu.sched_stack)
    , [_] "{rdi}" (cpu)
    , [dest] "r" (ap_init_stage2)
  );
  unreachable;
}

fn ap_init_stage2() void {
  _ = @atomicRmw(usize, &os.platform.smp.cpus_left, .Sub, 1, .AcqRel);
  // Wait for tasks
  asm volatile("int $0x6C");
  unreachable;
}

pub fn spin_hint() void {
  asm volatile("pause");
}

pub fn await_interrupt() void {
  asm volatile(
    \\sti
    \\hlt
    \\cli
    :
    :
    : "memory"
  );
}

pub fn debugputch(ch: u8) void {
  ports.outb(0xe9, ch);
  serial.port(1).write(ch);
  serial.port(2).write(ch);
  serial.port(3).write(ch);
  serial.port(4).write(ch);
}
