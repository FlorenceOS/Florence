const os = @import("root").os;
const lib = @import("lib");

const log = lib.output.log.scoped(.{
    .prefix = "Interrupts",
    .filter = .info,
}).write;

const msr = @import("aarch64.zig").msr;

pub const InterruptState = bool;

pub fn get_and_disable_interrupts() InterruptState {
    // Get interrupt mask flag
    var daif = msr(u64, "DAIF").read();

    // Set the flag
    msr(u4, "DAIFSET").writeImm(2);

    // Check if it was set
    return (daif >> 7) & 1 == 0;
}

pub fn set_interrupts(s: InterruptState) void {
    if (s) {
        // Enable interrupts
        msr(u4, "DAIFCLR").writeImm(2);
    } else {
        // Disable interrupts
        msr(u4, "DAIFSET").writeImm(2);
    }
}

pub const InterruptFrame = extern struct {
    spsr: u64,
    pc: u64,
    x31: u64,
    x30: u64,
    x29: u64,
    x28: u64,
    x27: u64,
    x26: u64,
    x25: u64,
    x24: u64,
    x23: u64,
    x22: u64,
    x21: u64,
    x20: u64,
    x19: u64,
    x18: u64,
    x17: u64,
    x16: u64,
    x15: u64,
    x14: u64,
    x13: u64,
    x12: u64,
    x11: u64,
    x10: u64,
    x9: u64,
    x8: u64,
    x7: u64,
    x6: u64,
    x5: u64,
    x4: u64,
    x3: u64,
    x2: u64,
    sp: u64,
    _: u64 = undefined,
    x1: u64,
    x0: u64,

    pub fn format(self: *const @This(), fmt: anytype) void {
        fmt("  X0 ={0X} X1 ={0X} X2 ={0X} X3 ={0X}\n", .{ self.x0, self.x1, self.x2, self.x3 });
        fmt("  X4 ={0X} X5 ={0X} X6 ={0X} X7 ={0X}\n", .{ self.x4, self.x5, self.x6, self.x7 });
        fmt("  X8 ={0X} X9 ={0X} X10={0X} X11={0X}\n", .{ self.x8, self.x9, self.x10, self.x11 });
        fmt("  X12={0X} X13={0X} X14={0X} X15={0X}\n", .{ self.x12, self.x13, self.x14, self.x15 });
        fmt("  X16={0X} X17={0X} X18={0X} X19={0X}\n", .{ self.x16, self.x17, self.x18, self.x19 });
        fmt("  X20={0X} X21={0X} X22={0X} X23={0X}\n", .{ self.x20, self.x21, self.x22, self.x23 });
        fmt("  X24={0X} X25={0X} X26={0X} X27={0X}\n", .{ self.x24, self.x25, self.x26, self.x27 });
        fmt("  X28={0X} X29={0X} X30={0X} X31={0X}\n", .{ self.x28, self.x29, self.x30, self.x31 });
        fmt("  PC ={0X} SP ={0X} SPSR={0X}", .{ self.pc, self.sp, self.spsr });
    }

    pub fn trace_stack(self: *const @This()) void {
        os.kernel.debug.dumpFrame(self.x29, self.pc);
    }
};

comptime {
    asm (
        \\handle_interrupt_on_stack:
        \\MRS X1, SP_EL0
        \\STP X1, XZR, [X0, #-0x20]
        \\
        \\MSR SP_EL0, X0 // Use this stack
        \\
        \\LDP X1, X0, [SP], 0x10
        \\MSR SPSel, #0 // Switch stacks
        \\STP X1, X0, [SP, #-0x10]!
        \\
        \\SUB SP, SP, #0x10
        \\
        \\interrupt_common:
        \\STP X3,  X2,  [SP, #-0x10]!
        \\STP X5,  X4,  [SP, #-0x10]!
        \\STP X7,  X6,  [SP, #-0x10]!
        \\STP X9,  X8,  [SP, #-0x10]!
        \\STP X11, X10, [SP, #-0x10]!
        \\STP X13, X12, [SP, #-0x10]!
        \\STP X15, X14, [SP, #-0x10]!
        \\STP X17, X16, [SP, #-0x10]!
        \\STP X19, X18, [SP, #-0x10]!
        \\STP X21, X20, [SP, #-0x10]!
        \\STP X23, X22, [SP, #-0x10]!
        \\STP X25, X24, [SP, #-0x10]!
        \\STP X27, X26, [SP, #-0x10]!
        \\STP X29, X28, [SP, #-0x10]!
        \\STP X31, X30, [SP, #-0x10]!
        \\MRS X0, SPSR_EL1
        \\MRS X1, ELR_EL1
        \\STP X0,  X1, [SP, #-0x10]!
        \\MOV X0,  SP
        \\BL interrupt_handler
        \\LDP X0,  X1,  [SP], 0x10
        \\MSR SPSR_EL1, X0
        \\MSR ELR_EL1, X1
        \\LDP X31, X30, [SP], 0x10
        \\LDP X29, X28, [SP], 0x10
        \\LDP X27, X26, [SP], 0x10
        \\LDP X25, X24, [SP], 0x10
        \\LDP X23, X22, [SP], 0x10
        \\LDP X21, X20, [SP], 0x10
        \\LDP X19, X18, [SP], 0x10
        \\LDP X17, X16, [SP], 0x10
        \\LDP X15, X14, [SP], 0x10
        \\LDP X13, X12, [SP], 0x10
        \\LDP X11, X10, [SP], 0x10
        \\LDP X9,  X8,  [SP], 0x10
        \\LDP X7,  X6,  [SP], 0x10
        \\LDP X5,  X4,  [SP], 0x10
        \\LDP X3,  X2,  [SP], 0x10
        \\
        \\LDP X1,  XZR, [SP], 0x10
        \\MRS X0, SPSel
        \\CBNZ X0, .int_stack_ret
        \\ // Return from non-interrupt stack
        \\
        \\MSR SPSel, #1
        \\STP X1,  XZR, [SP, #-0x20]
        \\MSR SPSel, #0
        \\LDP X1,  X0,  [SP], 0x10
        \\MSR SPSel, #1
        \\STP X1,  X0,  [SP, #-0x10]
        \\LDP X1,  XZR, [SP, #-0x20]
        \\MSR SP_EL0, X1
        \\LDP X1,  X0,  [SP, #-0x10]
        \\MSR SPSel, #0
        \\ERET
        \\
        \\.int_stack_ret:
        \\ // Return from int stack
        \\
        \\MSR SP_EL0, X1
        \\LDP X1,  X0,  [SP], 0x10
        \\MSR SPSel, #0
        \\ERET
    );
}

/// The vector which uses the already selected interrupt stack
export fn interrupt_irq_stack() callconv(.Naked) void {
    asm volatile (
        \\STP X1, X0, [SP, #-0x10]!
        \\
        \\MRS X1, SP_EL0
        \\STP X1, XZR, [SP, #-0x10]!
        \\
        \\B interrupt_common
    );
    unreachable;
}

/// The vector which switches to the per-CPU scheduler stack
export fn interrupt_sched_stack() callconv(.Naked) void {
    asm volatile (
        \\STP X1, X0, [SP, #-0x10]!
        \\
        \\MRS X0, TPIDR_EL1 // Get the current cpu struct
        \\LDR X0, [X0, %[sched_stack_offset]] // Get the CPU scheduler stack
        \\
        \\B handle_interrupt_on_stack
        :
        : [sched_stack_offset] "i" (@as(usize, @offsetOf(os.platform.smp.CoreData, "sched_stack")))
    );
    unreachable;
}

/// The vector which switches to the per-task syscall stack
export fn interrupt_syscall_stack() callconv(.Naked) void {
    asm volatile (
        \\STP X1, X0, [SP, #-0x10]!
        \\
        \\MRS X0, TPIDR_EL1 // Get the current cpu struct
        \\LDR X0, [X0, %[task_offset]] // Get the task
        \\LDR X0, [X0, %[syscall_stack_offset]]
        \\
        \\B handle_interrupt_on_stack
        :
        : [task_offset] "i" (@as(usize, @offsetOf(os.platform.smp.CoreData, "current_task"))),
          [syscall_stack_offset] "i" (@as(usize, @offsetOf(os.thread.Task, "stack")))
    );
    unreachable;
}

/// The handler for everything else, which should cause some kind
/// of panic or similar.
export fn unhandled_vector() callconv(.Naked) void {
    // We don't plan on returning, calling the scheduler
    // nor enabling interrupts in this handler one, so
    // we can just use any handler here
    asm volatile (
        \\B interrupt_irq_stack
    );
    unreachable;
}

comptime {
    asm (
        \\.section .text.evt
        \\.balign 0x800
        \\.global exception_vector_table; exception_vector_table:
        \\ // Normal IRQs/scheduler calls from within kernel
        \\.balign 0x80; B interrupt_sched_stack // curr_el_sp0_sync
        \\.balign 0x80; B interrupt_irq_stack   // curr_el_sp0_irq
        \\.balign 0x80; B interrupt_irq_stack   // curr_el_sp0_fiq
        \\.balign 0x80; B unhandled_vector      // curr_el_sp0_serror
        \\ // The following 4 are unsupported as we only use spx with interrupts disabled,
        \\ // in a context where a fail probably shouldn't be handled either.
        \\.balign 0x80; B unhandled_vector // curr_el_spx_sync
        \\.balign 0x80; B unhandled_vector // curr_el_spx_irq
        \\.balign 0x80; B unhandled_vector // curr_el_spx_fiq
        \\.balign 0x80; B unhandled_vector // curr_el_spx_serror
        \\ // Userspace IRQs or syscalls
        \\.balign 0x80; B interrupt_syscall_stack // lower_el_aarch64_sync
        \\.balign 0x80; B interrupt_irq_stack     // lower_el_aarch64_irq
        \\.balign 0x80; B interrupt_irq_stack     // lower_el_aarch64_fiq
        \\.balign 0x80; B interrupt_syscall_stack // lower_el_aarch64_serror
        \\ // 32 bit Userspace IRQs or syscalls
        \\.balign 0x80; B interrupt_syscall_stack // lower_el_aarch32_sync
        \\.balign 0x80; B interrupt_irq_stack     // lower_el_aarch32_irq
        \\.balign 0x80; B interrupt_irq_stack     // lower_el_aarch32_fiq
        \\.balign 0x80; B interrupt_syscall_stack // lower_el_aarch32_serror
    );
}

extern const exception_vector_table: [0x800]u8;

pub fn install_vector_table() void {
    asm volatile (
        \\MSR VBAR_EL1, %[evt]
        :
        : [evt] "r" (&exception_vector_table)
    );
}

fn do_stack_call(frame: *InterruptFrame) void {
    const fun = @intToPtr(fn (*os.platform.InterruptFrame, usize) void, frame.x2);
    const ctx: usize = frame.x1;
    fun(frame, ctx);
}

export fn interrupt_handler(frame: *InterruptFrame) callconv(.C) void {
    const esr = asm volatile ("MRS %[esr], ESR_EL1"
        : [esr] "=r" (-> u64)
    );

    const ec = (esr >> 26) & 0x3f;
    const iss = esr & 0x1ffffff;

    const userspace_process = if ((frame.spsr & 0xF) == 0) os.kernel.process.currentProcess() else null;

    const far = asm volatile ("MRS %[esr], FAR_EL1"
        : [esr] "=r" (-> u64)
    );

    const wnr = (iss >> 6) & 1;
    const dfsc = iss & 0x3f;

    // Assume present == !translation fault
    const present = (dfsc & 0b111100) != 0b000100;

    if (ec == 0b111100) {
        log(null, "BRK instruction execution in AArch64 state\n", .{});
        os.platform.hang();
    }

    switch (ec) {
        else => {
            log(null,
                \\EC = 0x{X}
                \\Frame dump:
                \\{}
            , .{ ec, frame });
            frame.trace_stack();
            @panic("Unknown EC!");
        },
        0b00000000 => {
            log(null, "Frame dump:\n{}", .{frame});
            frame.trace_stack();
            @panic("Unknown reason in EC!");
        },
        0b00100100 => { // Data abort from userspace
            userspace_process.?.onPageFault(far, present, if (wnr == 1) .Write else .Read, frame);
        },
        0b00100101 => { // Data abort from kernel
            os.platform.page_fault(far, present, if (wnr == 1) .Write else .Read, frame);
        },
        0b00100000 => { // Instruction fault from userspace
            userspace_process.?.onPageFault(far, false, .InstructionFetch, frame);
        },
        0b00100001 => { // Instruction fault from kernel
            os.platform.page_fault(far, false, .InstructionFetch, frame);
        },
        0b00010101 => { // SVC instruction execution in AArch64 state
            if (userspace_process) |p| {
                p.handleSyscall(frame);
            } else {
                // Figure out which call this is
                switch (@truncate(u16, iss)) {
                    else => @panic("Unknown SVC"),

                    'S' => do_stack_call(frame),
                }
            }
        },
    }
}

pub fn set_interrupt_stack(int_stack: usize) void {
    const current_stack = asm volatile ("MRS %[res], SPSel"
        : [res] "=r" (-> u64)
    );

    if (current_stack != 0) @panic("Cannot set interrupt stack while using it!");

    asm volatile (
        \\ MSR SPSel, #1
        \\ MOV SP, %[int_stack]
        \\ MSR SPSel, #0
        :
        : [int_stack] "r" (int_stack)
    );
}
