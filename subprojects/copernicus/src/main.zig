const std = @import("std");

fn logStr(str: []const u8) void {
    switch (@import("builtin").target.cpu.arch) {
        .x86_64 => {
            // zig fmt: off
            asm volatile(
                \\int $0x80
                \\
                :
                : [fd] "{rdi}" (@as(u64, 2))
                , [str] "{rsi}" (@ptrToInt(str.ptr))
                , [len] "{rdx}" (str.len)
                , [syscall_num] "{rax}" (@as(u64, 1))
            );
            // zig fmt: on
        },
        .aarch64 => {
            // zig fmt: off
            asm volatile(
                \\svc #0
                \\
                :
                : [fd] "{X0}" (@as(u64, 2))
                , [str] "{X1}" (@ptrToInt(str.ptr))
                , [len] "{X2}" (str.len)
                , [syscall_num] "{X8}" (@as(u64, 64))
            );
            // zig fmt: on
        },
        else => @compileError("logStr not implemented"),
    }
}

fn exit(exit_code: u64) noreturn {
    switch (@import("builtin").target.cpu.arch) {
        .x86_64 => {
            // zig fmt: off
            asm volatile(
                \\int $0x80
                \\
                :
                : [num] "{rdi}" (exit_code)
                , [syscall_num] "{rax}" (@as(u64, 60))
            );
            // zig fmt: on
            unreachable;
        },
        .aarch64 => {
            // zig fmt: off
            asm volatile(
                \\svc #0
                \\
                :
                : [num] "{X0}" (exit_code)
                , [syscall_num] "{X8}" (@as(u64, 93))
            );
            // zig fmt: on
            unreachable;
        },
        else => @compileError("exit not implemented"),
    }
}

export fn _start() linksection(".text.entry") void {
    logStr("Hello, userspace!\n");
    exit(0);
}
