pub const paging = @import("paging.zig");

pub const is_5levelpaging = paging.is_5levelpaging;

const interrupts = @import("interrupts.zig");
const setup_gdt = @import("gdt.zig").setup_gdt;
const serial = @import("serial.zig");

const os = @import("root").os;

const pmm    = os.memory.pmm;
const vmm    = os.memory.vmm;

const scheduler = os.thread.scheduler;
const Task      = os.thread.Task;

const pci   = os.platform.pci;

const range = os.lib.range;

const std = @import("std");
const assert = std.debug.assert;

pub const InterruptFrame = interrupts.InterruptFrame;

pub const paging_root = u64;

pub const page_sizes =
  [_]u64 {
    0x1000,
    0x200000,
    0x40000000,
    0x8000000000,
  };

pub fn platform_init() !void {
  try os.platform.acpi.init_acpi();
  try os.platform.pci.init_pci();
}

pub fn platform_early_init() void {
  serial.init();
  try interrupts.init_interrupts();
  setup_gdt();
  os.memory.paging.init();

  asm volatile("sti");
}

pub fn read_msr(comptime T: type, msr_num: u32) T {
  assert(T == u64);

  var low: u32 = undefined;
  var high: u32 = undefined;
  asm volatile("rdmsr" : [_]"={eax}"(low), [_]"={edx}"(high) : [_]"{ecx}"(msr_num));
  return (@as(u64, high) << 32) | @as(u64, low);
}

pub fn write_msr(comptime T: type, msr_num: u32, val: T) void {
  assert(T == u64);

  const low = @intCast(u32, val & 0xFFFFFFFF);
  const high = @intCast(u32, val >> 32);
  asm volatile("wrmsr" :: [_]"{eax}"(low), [_]"{edx}"(high), [_]"{ecx}"(msr_num));
}

pub fn msr(comptime T: type, comptime msr_num: u32) type {
  return struct {
    pub fn read() T {
      return read_msr(T, msr_num);
    }

    pub fn write(val: T) void {
      write_msr(T, msr_num, val);
    }
  };
}

pub fn reg(comptime T: type, comptime name: []const u8) type {
  return struct {
    pub fn read() T {
      return asm volatile(
        "mov %%" ++ name ++ ", %[out]"
        : [out]"=r"(-> T)
      );
    }

    pub fn write(val: T) void {
      asm volatile(
        "mov %[in], %%" ++ name
        :
        : [in]"r"(val)
      );
    }
  };
}

fn request(addr: pci.Addr, offset: pci.regoff) void {
  const val = 1 << 31
    | @as(u32, offset)
    | @as(u32, addr.function) << 8
    | @as(u32, addr.device) << 11
    | @as(u32, addr.bus) << 16
  ;

  outl(0xCF8, val);
}

pub fn pci_read(comptime T: type, addr: pci.Addr, offset: pci.regoff) T {
  request(addr, offset);
  return in(T, 0xCFC + @as(u16, offset % 4));
}

pub fn pci_write(comptime T: type, addr: pci.Addr, offset: pci.regoff, value: T) void {
  request(addr, offset);
  out(T, 0xCFC + @as(u16, offset % 4), value);
}

pub const InterruptState = bool;

pub fn eflags() u64 {
  return asm volatile(
    \\pushfq
    \\cli
    \\pop %[flags]
    : [flags] "=r" (-> u64)
  );
}

pub fn get_and_disable_interrupts() InterruptState {
  return eflags() & 0x200 == 0x200;
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

pub fn fill_cpuid(res: anytype, leaf: u32) bool {
  if(leaf & 0x7FFFFFFF != 0) {
    if(!check_has_cpuid_leaf(leaf))
      return false;
  }

  var eax: u32 = undefined;
  var ebx: u32 = undefined;
  var edx: u32 = undefined;
  var ecx: u32 = undefined;

  asm volatile(
    \\cpuid
    : [eax] "={eax}" (eax)
    , [ebx] "={ebx}" (ebx)
    , [edx] "={edx}" (edx)
    , [ecx] "={ecx}" (ecx)
    : [leaf] "{eax}" (leaf)
  );
  return true;
}

pub fn check_has_cpuid_leaf(leaf: u32) bool {
  const max_func = cpuid(leaf & 0x80000000).?.eax;
  return leaf <= max_func;
}

const default_cpuid = struct {
  eax: u32,
  ebx: u32,
  edx: u32,
  ecx: u32,
};

pub fn cpuid(leaf: u32) ?default_cpuid {
  var result: default_cpuid = undefined;
  if(fill_cpuid(&result, leaf))
    return result;
  return null;
}

pub const TaskData = struct {
  stack: ?*[task_stack_size]u8 = null,
};

const task_stack_size = 1024 * 16;

// https://github.com/ziglang/zig/issues/3857

// Sets 
fn task_fork_impl(frame: *InterruptFrame) !void {
  const new_task = @intToPtr(*Task, frame.rax);
  const current_task = get_current_task();

  scheduler.ready.enqueue(current_task);

  frame.rax = 0;

  new_task.registers = frame.*;
  current_task.registers = frame.*;

  current_task.registers.rbx = 0;
  frame.rbx = 1;

  set_current_task(new_task);
}

pub fn task_fork_handler(frame: *InterruptFrame) void {
  task_fork_impl(frame) catch |err| {
    frame.rax = 1;
    frame.rbx = @errorToInt(err);
  };
}

const stack_allocator = vmm.backed(.Ephemeral);

pub fn new_task_call(new_task: *Task, func: anytype, args: anytype) !void {
  var had_error: u64 = undefined;
  var result: u64 = undefined;

  new_task.platform_data.stack = try stack_allocator.create([task_stack_size]u8);
  errdefer stack_allocator.destroy(new_task.platform_data.stack.?);

  // task_fork()
  asm volatile(
    \\int $0x6A
    : [err] "={rax}" (had_error)
    , [res] "={rbx}" (result)
    : [new_task] "{rax}" (new_task)
  );

  if(had_error == 1)
    return @intToError(@intCast(std.meta.Int(.unsigned, @sizeOf(anyerror) * 8), result));

  // Guaranteed to be run first
  if(result == 1) {
    // Switch stack
    // https://github.com/ziglang/zig/issues/3857
    // @call(.{
    //   .modifier = .always_inline,
    //   .stack = @alignCast(16, new_task.platform_data.stack.?)[0..task_stack_size - 16],
    // }, new_task_call_part_2, .{func, args_ptr});
    var args_ptr = &args;
    asm volatile(
      ""
      : [_] "={rax}" (args_ptr)
      : [_] "{rsp}" (@ptrToInt(&new_task.platform_data.stack.?[task_stack_size - 16]))
      , [_] "{rax}" (args_ptr)
      : "memory"
    );
    new_task_call_part_2(func, args_ptr);
  }
}

fn new_task_call_part_2(func: anytype, args_ptr: anytype) noreturn {
  const new_args = args_ptr.*;
  // Let our parent task resume now that we've safely copied
  // the function arguments onto our stack
  scheduler.yield();
  @call(.{}, func, new_args) catch |err| {
    os.log("Task exited with error: {}\n", .{@errorName(err)});
    os.platform.hang();
  };
  scheduler.exit_task();
}

pub fn yield_to_task(t: *Task) void {
  asm volatile(
    \\int $0x6B
    :
    : [_] "{rax}" (t)
    : "memory"
  );
}

pub const self_exited = interrupts.self_exited;

pub const IA32_APIC_BASE = msr(u64, 0x0000001B);
pub const KernelGSBase   = msr(u64, 0xC0000102);

pub fn set_current_task(task_ptr: *Task) void {
  KernelGSBase.write(@ptrToInt(task_ptr));
}

pub fn get_current_task() *Task {
  return @intToPtr(*Task, KernelGSBase.read());
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

pub fn out(comptime T: type, port: u16, value: T) void {
  switch(T) {
    u8  => outb(port, value),
    u16 => outw(port, value),
    u32 => outl(port, value),
    else => @compileError("No out instruction for this type"),
  }
}

pub fn in(comptime T: type, port: u16) T {
  return switch(T) {
    u8  => inb(port),
    u16 => inw(port),
    u32 => inl(port),
    else => @compileError("No in instruction for this type"),
  };
}

pub fn outb(port: u16, val: u8) void {
  asm volatile (
    "outb %[val], %[port]\n\t"
    :
    : [val] "{al}"(val), [port] "N{dx}"(port)
  );
}

pub fn outw(port: u16, val: u16) void {
  asm volatile (
    "outw %[val], %[port]\n\t"
    :
    : [val] "{ax}"(val), [port] "N{dx}"(port)
  );
}

pub fn outl(port: u16, val: u32) void {
  asm volatile (
    "outl %[val], %[port]\n\t"
    :
    : [val] "{eax}"(val), [port] "N{dx}"(port)
  );
}

pub fn inb(port: u16) u8 {
  return asm volatile (
    "inb %[port], %[result]\n\t"
    : [result] "={al}" (-> u8)
    : [port]   "N{dx}" (port)
  );
}

pub fn inw(port: u16) u16 {
  return asm volatile (
    "inw %[port], %[result]\n\t"
    : [result] "={ax}" (-> u16)
    : [port]   "N{dx}" (port)
  );
}

pub fn inl(port: u16) u32 {
  return asm volatile (
    "inl %[port], %[result]\n\t"
    : [result] "={eax}" (-> u32)
    : [port]   "N{dx}" (port)
  );
}

pub fn debugputch(ch: u8) void {
  outb(0xe9, ch);
  // serial.port(1).write(ch);
  // serial.port(2).write(ch);
  // serial.port(3).write(ch);
  // serial.port(4).write(ch);
}
