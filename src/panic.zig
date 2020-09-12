const StackTrace = @import("builtin").StackTrace;
const log = @import("logger.zig").log;

pub fn breakpoint_panic(message: ?[]const u8, stack_trace: ?*StackTrace) noreturn {
  @breakpoint();
  unreachable;
}

pub fn panic(message: ?[]const u8, stack_trace: ?*StackTrace) noreturn {
  if(message != null) {
    log("PANIC: {}!\n", .{message});
  }
  else {
    log("PANIC!!\n", .{});
  }

  if(stack_trace != null) {
    log("TODO: print stack trace.\nI bet this is very helpful. No problem.\n", .{});
  } else {
    log("idfk I didn't get a stack trace.\n", .{});
  }

  while(true) { @breakpoint(); }
  unreachable;
}
