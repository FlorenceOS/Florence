const os = @import("root").os;

const config = @import("config");

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
    if (comptime !config.kernel.x86_64.allow_syscall_instr)
        return;

    regs.IA32_LSTAR.write(@ptrToInt(interrupts.syscall_handler));
    // Clear everything but the res1 bit (bit 1)
    regs.IA32_FMASK.write(@truncate(u22, ~@as(u64, 1 << 1)));

    comptime {
        if (gdt.selector.data64 != gdt.selector.code64 + 8)
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
    if (s) {
        asm volatile (
            \\sti
        );
    } else {
        asm volatile (
            \\cli
        );
    }
}

pub fn platform_init() !void {
    try os.platform.acpi.init_acpi();

    @import("ps2.zig").init();

    set_interrupts(true);

    @import("vmware.zig").init();

    try os.platform.pci.init_pci();
}

pub fn platform_early_init() void {
    // Set SMP metadata for the first CPU
    os.platform.smp.prepare();

    serial.init();

    // Load IDT
    interrupts.init_interrupts();

    // Init BSP GDT
    os.platform.smp.cpus[0].platform_data.gdt.load();

    os.memory.paging.init();
}

pub fn bsp_pre_scheduler_init() void {
    idt.load_idt();

    apic.enable();

    setup_syscall_instr();

    const cpu = &os.platform.smp.cpus[0];

    // Init BSP TSS
    cpu.platform_data.shared_tss = .{};
    cpu.platform_data.shared_tss.set_interrupt_stack(cpu.int_stack);
    cpu.platform_data.shared_tss.set_scheduler_stack(cpu.sched_stack);
    // Load BSP TSS
    cpu.platform_data.gdt.update_tss(&cpu.platform_data.shared_tss);
}

pub fn ap_init() void {
    os.memory.paging.kernel_context.apply();
    idt.load_idt();
    setup_syscall_instr();

    const cpu = os.platform.thread.get_current_cpu();

    cpu.platform_data.gdt.load();

    cpu.platform_data.shared_tss = .{};
    cpu.platform_data.shared_tss.set_interrupt_stack(cpu.int_stack);
    cpu.platform_data.shared_tss.set_scheduler_stack(cpu.sched_stack);
    cpu.platform_data.gdt.update_tss(&cpu.platform_data.shared_tss);

    apic.enable();
}

pub fn spin_hint() void {
    asm volatile ("pause");
}

pub fn await_interrupt() void {
    asm volatile (
        \\sti
        \\hlt
        \\cli
        :
        :
        : "memory"
    );
}

pub fn debugputch(ch: u8) void {
    if (config.kernel.x86_64.e9.enable)
        ports.outb(0xe9, ch);

    inline for (config.kernel.x86_64.serial.enabled_ports) |port| {
        serial.port(port).write(ch);
    }
}

pub fn clock() usize {
    var eax: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("rdtsc"
        : [_] "={eax}" (eax),
          [_] "={edx}" (edx)
    );
    return @as(usize, eax) + (@as(usize, edx) << 32);
}
