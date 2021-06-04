const std = @import("std");
const exec = @import("../../buildutil/exec.zig");
const config = @import("../../config/config.zig");

pub fn buildKernel(params: struct {
    builder: *std.build.Builder,
    arch: std.builtin.Arch,
    boot_proto: []const u8 = "stivale2",
    mode: ?std.builtin.Mode = null,
}) *std.build.LibExeObjStep {
    const arch = params.arch;
    const proto = params.boot_proto;

    const flork_path = "subprojects/flork/";

    const kernel_filename = params.builder.fmt("Flork_{s}_{s}", .{ proto, @tagName(arch) });
    const main_file = params.builder.fmt(flork_path ++ "src/boot/{s}.zig", .{proto});

    // For some reason if I define this directly in exec.makeExec param struct, it will
    // contain incorrect values. ZIG BUG
    const blob = .{
        .global_source_path = flork_path ++ "/src",
        .source_blob_name = kernel_filename,
    };

    const kernel = exec.makeExec(.{
        .builder = params.builder,
        .arch = arch,
        .ctx = .kernel,
        .filename = kernel_filename,
        .main = main_file,
        .source_blob = if (config.kernel.build_source_blob)
            blob
        else
            null,
        .mode = params.mode,
        .strip_symbols = config.kernel.strip_symbols,
    });

    kernel.addAssemblyFile(params.builder.fmt(flork_path ++ "src/boot/{s}_{s}.S", .{
        proto,
        @tagName(arch),
    }));
    kernel.setLinkerScriptPath(flork_path ++ "src/kernel/kernel.ld");

    const laipath = flork_path ++ "src/extern/lai/";
    kernel.addIncludeDir(laipath ++ "include/");
    const laiflags = &[_][]const u8{"-std=c99"};
    kernel.addCSourceFile(laipath ++ "core/error.c", laiflags);
    kernel.addCSourceFile(laipath ++ "core/eval.c", laiflags);
    kernel.addCSourceFile(laipath ++ "core/exec-operand.c", laiflags);
    kernel.addCSourceFile(laipath ++ "core/exec.c", laiflags);
    kernel.addCSourceFile(laipath ++ "core/libc.c", laiflags);
    kernel.addCSourceFile(laipath ++ "core/ns.c", laiflags);
    kernel.addCSourceFile(laipath ++ "core/object.c", laiflags);
    kernel.addCSourceFile(laipath ++ "core/opregion.c", laiflags);
    kernel.addCSourceFile(laipath ++ "core/os_methods.c", laiflags);
    kernel.addCSourceFile(laipath ++ "core/variable.c", laiflags);
    kernel.addCSourceFile(laipath ++ "core/vsnprintf.c", laiflags);
    kernel.addCSourceFile(laipath ++ "drivers/ec.c", laiflags);
    kernel.addCSourceFile(laipath ++ "drivers/timer.c", laiflags);
    if (arch == .x86_64)
        kernel.addCSourceFile(laipath ++ "helpers/pc-bios.c", laiflags);
    kernel.addCSourceFile(laipath ++ "helpers/pci.c", laiflags);
    kernel.addCSourceFile(laipath ++ "helpers/pm.c", laiflags);
    kernel.addCSourceFile(laipath ++ "helpers/resource.c", laiflags);
    kernel.addCSourceFile(laipath ++ "helpers/sci.c", laiflags);
    return kernel;
}
