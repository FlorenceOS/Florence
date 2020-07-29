const StackTrace = @import("builtin").StackTrace;
const log = @import("logger.zig").log;
const std = @import("std");
const arch = @import("builtin").arch;

pub fn panic(message: []const u8, stack_trace: ?*StackTrace) noreturn {
  log("PANIC: {}!\n", .{message});

  if(stack_trace != null) {
    log("TODO: print stack trace.\nI bet this is very helpful. No problem.\n", .{});
  } else {
    log("idfk I didn't get a stack trace.\n", .{});
  }

  while(true) { }
}
