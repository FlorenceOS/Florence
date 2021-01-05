const arch = @import("builtin").arch;

pub fn ident(name: []const u8) u64 {
  var result: u64 = 0;
  for(name) |c| {
    result <<= 8;
    result |= @as(u64, c);
  }
  return result;
}

pub const identifiers = enum(u64) {
  stack = ident("STAK"),
  exit = ident("EXIT"),
};

export fn do_syscall() u64 {
  switch(comptime arch) {
    .x86_64 => {
      return asm volatile(
        \\ syscall
        : [_] "={rax}" (-> u64)
        :
        : "rcx"
        , "r11"
      );
    },
    .aarch64 => {
      return asm volatile(
        \\ SVC #0x69
        : [_] "={X0}" (-> u64)
      );
    },
    else => unreachable,
  }
}

pub fn syscall_impl(comptime id: identifiers, comptime fntype: type) fntype {
  switch (@typeInfo(fntype)) {
    .Fn => |ft| {
      if(ret_t) |ft.return_type| {
        return
          asm volatile(
            \\jmp do_syscall
          );
      }
      return @intToPtr(fntype, @ptrToInt(do_syscall));
    },
    else => unreachable,
  }
}

pub const exit = syscall_impl(identifiers.exit, fn () noreturn);
