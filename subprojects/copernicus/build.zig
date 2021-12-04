const std = @import("std");
const exec = @import("../../buildutil/exec.zig");
const config = @import("../../config/config.zig");

const Arch = if (@hasField(std.builtin, "Arch")) std.builtin.Arch else std.Target.Cpu.Arch;

pub fn buildCopernicus(params: struct {
    builder: *std.build.Builder,
    arch: Arch,
}) !*std.build.InstallRawStep {
    const arch = params.arch;

    const copernicus_path = "subprojects/copernicus/";

    const copernicus_filename = params.builder.fmt("Copernicus_{s}", .{@tagName(arch)});
    const main_file = copernicus_path ++ "src/main.zig";

    // For some reason if I define this directly in exec.makeExec param struct, it will
    // contain incorrect values. ZIG BUG
    const source_blob = .{
        .global_source_path = copernicus_path ++ "/src",
        .source_blob_name = copernicus_filename,
    };

    const copernicus = exec.makeExec(.{
        .builder = params.builder,
        .arch = arch,
        .ctx = .userspace,
        .filename = copernicus_filename,
        .main = main_file,
        .source_blob = if (config.copernicus.build_source_blob)
            source_blob
        else
            null,
        .mode = config.copernicus.build_mode,
        .strip_symbols = config.copernicus.strip_symbols,
    });

    copernicus.setLinkerScriptPath(.{ .path = copernicus_path ++ "src/linker.ld" });

    return exec.binaryBlobSection(params.builder, copernicus, ".blob");
}
