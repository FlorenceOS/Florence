const StackTrace = @import("builtin").StackTrace;

const os = @import("root").os;

pub fn breakpoint_panic(message: ?[]const u8, stack_trace: ?*StackTrace) noreturn {
  @breakpoint();
  unreachable;
}

pub fn panic(message: ?[]const u8, stack_trace: ?*StackTrace) noreturn {
  if(message != null) {
    os.log("PANIC: {}!\n", .{message});
  }
  else {
    os.log("PANIC!!\n", .{});
  }

  if(stack_trace != null) {
    os.log("TODO: print stack trace.\nI bet this is very helpful. No problem.\n", .{});
  } else {
    os.log("idfk I didn't get a stack trace.\n", .{});
  }

  while(true) { @breakpoint(); }
  unreachable;
}
