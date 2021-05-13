const os = @import("root").os;
const std = @import("std");

const interrupts = @import("interrupts.zig");
const idt = @import("idt.zig");
const gdt = @import("gdt.zig");
const serial = @import("serial.zig");
const ports = @import("ports.zig");
const regs = @import("regs.zig");
const apic = @import("apic.zig");
const pci = os.platform.pci;

const Tss = @import("tss.zig").Tss;

pub const paging = @import("paging.zig");
pub const pci_space = @import("pci_space.zig");
pub const thread = @import("thread.zig");
pub const PagingRoot = u64;
pub const InterruptFrame = interrupts.InterruptFrame;
pub const InterruptState = interrupts.InterruptState;

pub const irq_eoi = apic.eoi;

fn setup_syscall_instr() void {
  if(comptime !os.config.kernel.x86_64.allow_syscall_instr)
    return;

  regs.IA32_LSTAR.write(@ptrToInt(interrupts.syscall_handler));
  // Clear everything but the res1 bit (bit 1)
  regs.IA32_FMASK.write(@truncate(u22, ~@as(u64, 1 << 1)));

  comptime {
    if(gdt.selector.data64 != gdt.selector.code64 + 8)
      @compileError("syscall instruction assumes this");
  }

  regs.IA32_STAR.write(@as(u64, gdt.selector.code64) << 32);

  // Allow syscall instructions
  regs.IA32_EFER.write(regs.IA32_EFER.read() | (1 << 0));
}

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

  if(comptime(os.config.kernel.x86_64.ps2.enable_keyboard)) {
    const ps2 = @import("ps2.zig");
    ps2.interrupt_vector = interrupts.allocate_vector();
    os.log("PS2: vector 0x{X}\n", .{ps2.interrupt_vector});

    interrupts.add_handler(ps2.interrupt_vector, ps2.handler, true, 3, 1);

    ps2.interrupt_gsi = apic.route_irq(0, 0x01, ps2.interrupt_vector);
    os.log("PS2: gsi 0x{X}\n", .{ps2.interrupt_gsi});
  }
  try os.platform.pci.init_pci();
}

pub fn platform_early_init() void {
  os.platform.smp.prepare();
  serial.init();
  interrupts.init_interrupts();
  os.platform.smp.cpus[0].platform_data.gdt.load();
  os.memory.paging.init();
}

pub fn bsp_pre_scheduler_init() void {
  idt.load_idt();

  apic.enable();

  setup_syscall_instr();

  const cpu = os.platform.thread.get_current_cpu();
  thread.bsp_task.platform_data.tss = os.vital(os.memory.vmm.backed(.Eternal).create(Tss), "alloc bsp tss");
  thread.bsp_task.platform_data.tss.* = .{};

  thread.bsp_task.platform_data.tss.set_interrupt_stack(cpu.int_stack);
  thread.bsp_task.platform_data.tss.set_scheduler_stack(cpu.sched_stack);
  thread.bsp_task.platform_data.load_state();
}

pub fn ap_init() noreturn {
  os.memory.paging.kernel_context.apply();
  idt.load_idt();
  setup_syscall_instr();

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

fn ap_init_stage2() noreturn {
  _ = @atomicRmw(usize, &os.platform.smp.cpus_left, .Sub, 1, .AcqRel);
  // Wait for tasks
  asm volatile(
    \\int %[boostrap_vector]
    \\
    :
    : [boostrap_vector] "i" (interrupts.boostrap_vector)
  );
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

pub fn clock() usize {
    var eax: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("rdtsc"
        : [_] "={eax}" (eax),
          [_] "={edx}" (edx),
    );
    return @as(usize, eax) + (@as(usize, edx) << 32);
}
