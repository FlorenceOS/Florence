const log = @import("../../logger.zig").log;

const idt = @import("idt.zig");

pub fn init_interrupts() !void {
  disable_pic();
  try idt.setup_idt();

  log("Enabling interrupts...\n", .{});
  asm volatile("sti");
}

fn disable_pic() void {
  log("Disabling PIC...\n", .{});
  {
    const outb = @import("x86_64.zig").outb;
    outb(0x20, 0x11);
    outb(0xa0, 0x11);
    outb(0x21, 0x20);
    outb(0xa1, 0x28);
    outb(0x21, 0b0000_0100);
    outb(0xa1, 0b0000_0010);

    outb(0x21, 0x01);
    outb(0xa1, 0x01);

    // Mask out all interrupts
    outb(0x21, 0xF);
    outb(0xa1, 0xF);
  }
}

fn name(intnum: u64) []const u8 {
  switch(intnum) {
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
    0x15 ... 0x1D => unreachable,
    0x1E => "Security Exception",

    else => unreachable,
  }
}

fn has_error_code(intnum: u64) bool {
  switch(intnum) {
    0x08          => true,
    0x0A ... 0x0E => true,
    0x11          => true,
    0x15 ... 0x1D => unreachable,
    0x1E          => true,
    0x1F          => unreachable,

    else => false,
  }
}

pub fn make_handler(comptime intnum: u64) idt.InterruptHandler {
  return struct {
    fn func() callconv(.Naked) void {
      if(!has_error_code(intnum)) {
        asm volatile(
          \\push $0
        );
      }
      asm volatile(
        \\push [intnum]
        \\jmp interrupt_common
        :
        : [intnum] "N{dx}" (@as(u8, intnum))
      );
    }
  }.func;
}

const InterruptFrame = packed struct {
  r15: u64,
  r14: u64,
  r13: u64,
  r12: u64,
  r11: u64,
  r10: u64,
  r9:  u64,
  r8:  u64,
  rdi: u64,
  rsi: u64,
  rbp: u64,
  rdx: u64,
  rcx: u64,
  rbx: u64,
  rax: u64,
  intnum: u64,
  ec:  u64,
  rip: u64,
  cs:  u64,
  eflags: u64,
  rsp: u64, 
  ss:  u64,
};

export fn interrupt_common() callconv(.Naked) void {
  asm volatile(
    \\.intel_syntax noprefix
    \\push rax
    \\push rbx
    \\push rcx
    \\push rdx
    \\push rbp
    \\push rsi
    \\push rdi
    \\push r8
    \\push r9
    \\push r10
    \\push r11
    \\push r12
    \\push r13
    \\push r14
    \\push r15
    \\mov rdi, rsp
    \\call interrupt_handler
    \\pop  r15
    \\pop  r14
    \\pop  r13
    \\pop  r12
    \\pop  r11
    \\pop  r10
    \\pop  r9
    \\pop  r8
    \\pop  rdi
    \\pop  rsi
    \\pop  rbp
    \\pop  rdx
    \\pop  rcx
    \\pop  rbx
    \\pop  rax
    \\add  rsp, 16 // Pop error code and interrupt number
    \\iretq
  );
}

export fn interrupt_handler(frame: u64) void {
  const int_frame = @intToPtr(*InterruptFrame, frame - @sizeOf(InterruptFrame));
  log("Got interrupt {x}\n", .{int_frame.ec});
  while(true) { }
}
