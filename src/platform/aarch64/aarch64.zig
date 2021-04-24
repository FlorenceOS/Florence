const os = @import("root").os;
const std = @import("std");

pub const paging = @import("paging.zig");
pub const thread = @import("thread.zig");

pub const InterruptFrame = interrupts.InterruptFrame;
pub const InterruptState = interrupts.InterruptState;
pub const get_and_disable_interrupts = interrupts.get_and_disable_interrupts;
pub const set_interrupts = interrupts.set_interrupts;

const interrupts = @import("interrupts.zig");

const pmm       = os.memory.pmm;
const bf        = os.lib.bitfields;

const assert = std.debug.assert;

pub fn msr(comptime T: type, comptime name: []const u8) type {
  return struct {
    pub fn read() T {
      return asm volatile(
        "MRS %[out], " ++ name
        : [out]"=r"(-> T)
      );
    }

    pub fn write(val: T) void {
      asm volatile(
        "MSR " ++ name ++ ", %[in]"
        :
        : [in]"r"(val)
      );
    }
  };
}

pub fn spin_hint() void {
  asm volatile("YIELD");
}

pub fn allowed_mapping_levels() usize {
  return 2;
}

pub fn platform_init() !void {
  try os.platform.acpi.init_acpi();
  try os.platform.pci.init_pci();
}

pub fn ap_init() void {
  os.memory.paging.kernel_context.apply();
  interrupts.install_vector_table();
}

pub fn debugputch(val: u8) void {

}

pub fn bsp_pre_scheduler_init() void {
  const cpu = os.platform.thread.get_current_cpu();
  thread.set_interrupt_stack(cpu.int_stack);
  interrupts.install_vector_table();
}

pub fn platform_early_init() void {
  os.platform.smp.prepare();
  os.memory.paging.init();
}

pub fn await_interrupt() void {
  asm volatile(
    \\ MSR DAIFCLR, 0x2
    \\ WFI
    \\ MSR DAIFSET, 0x2
    :
    :
    : "memory"
  );
}

pub fn prepare_paging() !void {

}
