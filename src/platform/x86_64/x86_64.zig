
const os = @import("root").os;
const std = @import("std");

const interrupts = @import("interrupts.zig");
const gdt = @import("gdt.zig");
const serial = @import("serial.zig");
const ports = @import("ports.zig");
const regs = @import("regs.zig");
const pci = os.platform.pci;

pub const paging = @import("paging.zig");
pub const pci_space = @import("pci_space.zig");
pub const thread = @import("thread.zig");
pub const PagingRoot = u64;
pub const InterruptFrame = interrupts.InterruptFrame;
pub const InterruptState = interrupts.InterruptState;

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
  try os.platform.pci.init_pci();
}

pub fn platform_early_init() void {
  os.platform.smp.prepare();
  os.thread.scheduler.init(&bsp_task);
  serial.init();
  try interrupts.init_interrupts();
  gdt.setup_gdt();
  os.memory.paging.init();

  set_interrupts(true);
}

pub fn ap_init() void {
  os.memory.paging.CurrentContext.apply();
  try interrupts.init_interrupts();
  gdt.setup_gdt();

  set_interrupts(true);
}

pub const kernel_gs_base = regs.MSR(u64, 0xC0000102);

pub fn set_current_cpu(cpu_ptr: *os.platform.smp.CoreData) void {
  kernel_gs_base.write(@ptrToInt(cpu_ptr));
}

pub fn get_current_cpu() *os.platform.smp.CoreData {
  return @intToPtr(*os.platform.smp.CoreData, kernel_gs_base.read());
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
