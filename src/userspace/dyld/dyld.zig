const arch = @import("builtin").arch;

pub const os = @import("../../os.zig");

pub export fn _start() callconv(.Naked) noreturn {
  switch(comptime arch) {
    .x86_64 => {
      asm volatile(
        \\ syscall
        \\ mov %%rax, %%rsp
        \\ .extern main
        \\ jmp main
        :
        : [_] "{rax}" (comptime os.userspace.syscalls.identifiers.stack)
      );
    },
    .aarch64 => {
      asm volatile(
        \\ SVC #69
        \\ MOV SP, X0
        \\ .extern main
        \\ B main
        :
        : [_] "{x0}" (comptime os.userspace.syscalls.identifiers.stack)
      );
    },
    else => unreachable,
  }
  unreachable;
}

export fn main() callconv(.Naked) noreturn {
  wrapped_main() catch |err| { };
  os.userspace.syscalls.exit();
}

fn wrapped_main() !void {
  os.log("Woop, I guess we're in userspace!\n", .{});

}
