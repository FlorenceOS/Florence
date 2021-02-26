const os = @import("root").os;
const std = @import("std");

const regs = @import("regs.zig");
const interrupts = @import("interrupts.zig");

pub var bsp_task: os.thread.Task = .{};

pub const kernel_gs_base = regs.MSR(u64, 0xC0000102);

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

  if(curr.platform_data.stack != null) {
    // TODO: Add URM
  }
  return curr;
}

pub const TaskData = struct {
  stack: ?*[task_stack_size]u8 = null,
};

const task_stack_size = 1024 * 16;

fn task_fork_impl(frame: *interrupts.InterruptFrame) !void {
  const new_task = @intToPtr(*os.thread.Task, frame.rax);
  const current_cpu = os.platform.thread.get_current_cpu();

  const current_task = current_cpu.current_task.?;

  current_cpu.executable_tasks.enqueue(current_task);

  frame.rax = 0;

  new_task.registers = frame.*;
  current_task.registers = frame.*;

  current_task.registers.rbx = 0;
  frame.rbx = 1;

  os.platform.set_current_task(new_task);
}

pub fn task_fork_handler(frame: *interrupts.InterruptFrame) void {
  task_fork_impl(frame) catch |err| {
    frame.rax = 1;
    frame.rbx = @errorToInt(err);
  };
}

const stack_allocator = os.memory.vmm.backed(.Ephemeral);

pub fn new_task_call(new_task: *os.thread.Task, func: anytype, args: anytype) !void {
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
  os.thread.scheduler.yield();
  @call(.{}, func, new_args) catch |err| {
    os.log("Task exited with error: {}\n", .{@errorName(err)});
    os.platform.hang();
  };
  os.thread.scheduler.exit_task();
}

pub fn yield(enqueue: bool) void {
  asm volatile(
    \\int $0x6B
    :
    : [_] "{rbx}" (@boolToInt(enqueue))
    : "memory"
  );
}
