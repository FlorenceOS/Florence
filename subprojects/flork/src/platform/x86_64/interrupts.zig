usingnamespace @import("root").preamble;

const platform = os.platform;
const range = lib.util.range.range;
const scheduler = os.thread.scheduler;

const idt = @import("idt.zig");
const gdt = @import("gdt.zig");
const pic = @import("pic.zig");
const apic = @import("apic.zig");
const thread = @import("thread.zig");

pub const num_handlers = 0x100;
pub const InterruptHandler = fn (*InterruptFrame) void;
pub const InterruptState = bool;

export var handlers: [256]InterruptHandler = [_]InterruptHandler{unhandled_interrupt} ** num_handlers;
var itable: *[256]idt.IdtEntry = undefined;
var raw_callbacks: [256](fn () callconv(.Naked) void) = undefined;

/// Use ist=2 for scheduler calls and ist=1 for interrupts
pub fn add_handler(idx: u8, f: InterruptHandler, interrupt: bool, priv_level: u2, ist: u3) void {
    itable[idx] = idt.entry(raw_callbacks[idx], interrupt, priv_level, ist);
    handlers[idx] = f;
}

pub const sched_call_vector: u8 = 0x31;
pub const syscall_vector: u8 = 0x32;
pub const ring_vector: u8 = 0x33;

var last_vector: u8 = ring_vector;

pub const spurious_vector: u8 = 0xFF;

pub fn allocate_vector() u8 {
    return @atomicRmw(u8, &last_vector, .Add, 1, .AcqRel) + 1;
}

pub fn init_interrupts() void {
    pic.disable();
    itable = &idt.idt;

    inline for (range(num_handlers)) |intnum| {
        raw_callbacks[intnum] = make_handler(intnum);
        add_handler(intnum, unhandled_interrupt, true, 0, 0);
    }

    add_handler(0x0E, page_fault_handler, true, 3, 1);
    add_handler(ring_vector, ring_handler, true, 0, 1);
    add_handler(sched_call_vector, os.platform.thread.sched_call_impl_handler, true, 0, 2);
    add_handler(spurious_vector, spurious_handler, true, 0, 1);
}

fn spurious_handler(_: *InterruptFrame) void {}

fn ring_handler(_: *InterruptFrame) void {
    apic.eoi();
}

fn type_page_fault(error_code: usize) platform.PageFaultAccess {
    if ((error_code & 0x10) != 0)
        return .InstructionFetch;
    if ((error_code & 0x2) != 0)
        return .Write;
    return .Read;
}

fn page_fault_handler(frame: *InterruptFrame) void {
    const page_fault_addr = asm ("mov %%cr2, %[addr]"
        : [addr] "=r" (-> usize)
    );
    const page_fault_type = type_page_fault(frame.ec);

    platform.page_fault(page_fault_addr, (frame.ec & 1) != 0, page_fault_type, frame);
}

fn unhandled_interrupt(frame: *InterruptFrame) void {
    os.log("Interrupts: Unhandled interrupt: {}!\n", .{frame.intnum});
    frame.dump();
    frame.trace_stack();
    os.platform.hang();
}

fn is_exception(intnum: u64) bool {
    return switch (intnum) {
        0x00...0x1F => true,

        else => false,
    };
}

fn name(intnum: u64) []const u8 {
    return switch (intnum) {
        0x00 => "Divide by zero",
        0x01 => "Debug",
        0x02 => "Non-maskable interrupt",
        0x03 => "Breakpoint",
        0x04 => "Overflow",
        0x05 => "Bound range exceeded",
        0x06 => "Invalid opcode",
        0x07 => "Device not available",
        0x08 => "Double fault",
        0x09 => "Coprocessor Segment Overrun",
        0x0A => "Invalid TSS",
        0x0B => "Segment Not Present",
        0x0C => "Stack-Segment Fault",
        0x0D => "General Protection Fault",
        0x0E => "Page Fault",
        0x0F => unreachable,
        0x10 => "x87 Floating-Point Exception",
        0x11 => "Alignment Check",
        0x12 => "Machine Check",
        0x13 => "SIMD Floating-Point Exception",
        0x14 => "Virtualization Exception",
        0x15...0x1D => unreachable,
        0x1E => "Security Exception",

        else => unreachable,
    };
}

fn has_error_code(intnum: u64) bool {
    return switch (intnum) {
        // Exceptions
        0x00...0x07 => false,
        0x08 => true,
        0x09 => false,
        0x0A...0x0E => true,
        0x0F...0x10 => false,
        0x11 => true,
        0x12...0x14 => false,
        //0x15 ... 0x1D => unreachable,
        0x1E => true,
        //0x1F          => unreachable,

        // Other interrupts
        else => false,
    };
}

pub fn make_handler(comptime intnum: u8) idt.InterruptHandler {
    return struct {
        fn func() callconv(.Naked) void {
            const ec = if (comptime (!has_error_code(intnum))) "push $0\n" else "";
            asm volatile (ec ++ "push %[intnum]\njmp interrupt_common\n"
                :
                : [intnum] "i" (@as(u8, intnum))
            );
        }
    }.func;
}

pub const InterruptFrame = packed struct {
    es: u64,
    ds: u64,
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rdi: u64,
    rsi: u64,
    rbp: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
    intnum: u64,
    ec: u64,
    rip: u64,
    cs: u64,
    eflags: u64,
    rsp: u64,
    ss: u64,

    pub fn dump(self: *const @This()) void {
        os.log("FRAME DUMP:\n", .{});
        os.log("RAX={x:0>16} RBX={x:0>16} RCX={x:0>16} RDX={x:0>16}\n", .{ self.rax, self.rbx, self.rcx, self.rdx });
        os.log("RSI={x:0>16} RDI={x:0>16} RBP={x:0>16} RSP={x:0>16}\n", .{ self.rsi, self.rdi, self.rbp, self.rsp });
        os.log("R8 ={x:0>16} R9 ={x:0>16} R10={x:0>16} R11={x:0>16}\n", .{ self.r8, self.r9, self.r10, self.r11 });
        os.log("R12={x:0>16} R13={x:0>16} R14={x:0>16} R15={x:0>16}\n", .{ self.r12, self.r13, self.r14, self.r15 });
        os.log("RIP={x:0>16} int={x:0>16} ec ={x:0>16}\n", .{ self.rip, self.intnum, self.ec });
    }

    pub fn trace_stack(self: *const @This()) void {
        os.kernel.debug.dumpFrame(self.rbp, self.rip);
    }
};

export fn interrupt_common() callconv(.Naked) void {
    asm volatile (
        \\push %%rax
        \\push %%rbx
        \\push %%rcx
        \\push %%rdx
        \\push %%rbp
        \\push %%rsi
        \\push %%rdi
        \\push %%r8
        \\push %%r9
        \\push %%r10
        \\push %%r11
        \\push %%r12
        \\push %%r13
        \\push %%r14
        \\push %%r15
        \\mov %%ds, %%rax
        \\push %%rax
        \\mov %%es, %%rax
        \\push %%rax
        \\mov %%rsp, %%rdi
        \\mov %[dsel], %%ax
        \\mov %%ax, %%es
        \\mov %%ax, %%ds
        \\call interrupt_handler
        \\pop %%rax
        \\mov %%rax, %%es
        \\pop %%rax
        \\mov %%rax, %%ds
        \\pop %%r15
        \\pop %%r14
        \\pop %%r13
        \\pop %%r12
        \\pop %%r11
        \\pop %%r10
        \\pop %%r9
        \\pop %%r8
        \\pop %%rdi
        \\pop %%rsi
        \\pop %%rbp
        \\pop %%rdx
        \\pop %%rcx
        \\pop %%rbx
        \\pop %%rax
        \\add $16, %%rsp // Pop error code and interrupt number
        \\iretq
        :
        : [dsel] "i" (gdt.selector.data64)
    );
    unreachable;
}

export fn interrupt_handler(frame: u64) void {
    const int_frame = @intToPtr(*InterruptFrame, frame);
    int_frame.intnum &= 0xFF;
    if (int_frame.intnum < num_handlers) {
        handlers[int_frame.intnum](int_frame);
    }
}

// Turns out GAS is so terrible we have to write a small assembler ourselves.
const swapgs = [_]u8{ 0x0F, 0x01, 0xF8 };
const sti = [_]u8{0xFB};
const rex = [_]u8{0x41};

fn pack_le(comptime T: type, comptime value: u32) [@sizeOf(T)]u8 {
    var result: [@sizeOf(T)]u8 = undefined;
    std.mem.writeIntLittle(T, &result, value);
    return result;
}

fn mov_gs_offset_rsp(comptime offset: u32) [9]u8 {
    return [_]u8{ 0x65, 0x48, 0x89, 0x24, 0x25 } ++ pack_le(u32, offset);
}

fn mov_rsp_gs_offset(comptime offset: u32) [9]u8 {
    return [_]u8{ 0x65, 0x48, 0x8B, 0x24, 0x25 } ++ pack_le(u32, offset);
}

fn mov_rsp_rsp_offset(comptime offset: u32) [8]u8 {
    return [_]u8{ 0x48, 0x8B, 0xA4, 0x24 } ++ pack_le(u32, offset);
}

fn push_gs_offset(comptime offset: u32) [8]u8 {
    return [_]u8{ 0x65, 0xFF, 0x34, 0x25 } ++ pack_le(u32, offset);
}

fn pushi32(comptime value: i32) [5]u8 {
    return [_]u8{0x68} ++ pack_le(i32, value);
}

fn pushi8(comptime value: i8) [2]u8 {
    return [_]u8{0x6A} ++ pack_le(i8, value);
}

fn push_reg(comptime regnum: u3) [1]u8 {
    return [_]u8{0x50 | @as(u8, regnum)};
}

// Assumes IA32_FMASK (0xC0000084) disables interrupts
const rsp_stash_offset =
    @offsetOf(os.platform.smp.CoreData, "platform_data") +
    @offsetOf(os.platform.thread.CoreData, "rsp_stash");
const task_offset = @offsetOf(os.platform.smp.CoreData, "current_task");
const kernel_stack_offset = @offsetOf(os.thread.Task, "stack");

const syscall_handler_bytes = [0]u8{}
// First make sure we get a proper stack pointer while
// saving away all the userspace registers.
    ++ swapgs // swapgs
    ++ mov_gs_offset_rsp(rsp_stash_offset) // mov gs:[rsp_stash_offset], rsp
    ++ mov_rsp_gs_offset(task_offset) // mov rsp, gs:[task_offset]
    ++ mov_rsp_rsp_offset(kernel_stack_offset) // mov rsp, [rsp + kernel_stack_offset]

// Now we have a kernel stack in rsp
// Set up an iret frame
    ++ pushi8(gdt.selector.userdata64) // push user_data_sel         // iret ss
    ++ push_gs_offset(rsp_stash_offset) // push gs:[rsp_stash_offset] // iret rsp
    ++ rex ++ push_reg(11 - 8) // push r11                   // iret rflags
    ++ pushi8(gdt.selector.usercode64) // push user_code_sel         // iret cs
    ++ push_reg(1) // push rcx                   // iret rip
    ++ swapgs ++ sti

// Now let's set up the rest of the interrupt frame
    ++ pushi8(0) // push 0                     // error code
    ++ pushi32(syscall_vector) // push 0x80                  // interrupt vector
;

fn hex_chr(comptime value: u4) u8 {
    return "0123456789ABCDEF"[value];
}

fn hex_str(comptime value: u8) [2]u8 {
    var buf: [2]u8 = undefined;
    buf[0] = hex_chr(@truncate(u4, value >> 4));
    buf[1] = hex_chr(@truncate(u4, value));
    return buf;
}

pub fn syscall_handler() callconv(.Naked) void {
    // https://github.com/ziglang/zig/issues/8644
    comptime var syscall_handler_asm: []const u8 = &[_]u8{};
    inline for (syscall_handler_bytes) |b|
        syscall_handler_asm = syscall_handler_asm ++ [_]u8{ '.', 'b', 'y', 't', 'e', ' ', '0', 'x' } ++ hex_str(b) ++ [_]u8{'\n'};

    asm volatile (syscall_handler_asm ++
            \\jmp interrupt_common
            \\
    );
    unreachable;
}
