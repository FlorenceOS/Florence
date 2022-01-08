const std = @import("std");

const Arch = if (@hasField(std.builtin, "Arch")) std.builtin.Arch else std.Target.Cpu.Arch;

pub const Context = enum {
    kernel,
    userspace,
};

pub const TransformFileCommandStep = struct {
    step: std.build.Step,
    output_path: []const u8,
    fn run_command(s: *std.build.Step) !void {
        _ = s;
    }
};

fn make_transform(b: *std.build.Builder, dep: *std.build.Step, command: [][]const u8, output_path: []const u8) !*TransformFileCommandStep {
    const transform = try b.allocator.create(TransformFileCommandStep);

    transform.output_path = output_path;
    transform.step = std.build.Step.init(.custom, "", b.allocator, TransformFileCommandStep.run_command);

    const command_step = b.addSystemCommand(command);

    command_step.step.dependOn(dep);
    transform.step.dependOn(&command_step.step);

    return transform;
}

pub fn binaryBlobSection(b: *std.build.Builder, elf: *std.build.LibExeObjStep, section_name: []const u8) *std.build.InstallRawStep {
    return elf.installRaw(b.fmt("{s}.bin", .{elf.out_filename}), .{
        .only_section_name = section_name,
        .format = .bin,
    });
}

var source_blob_step: ?std.build.Step = null;
var source_blob_path: []const u8 = undefined;

const tar = @import("../lib/format/tar.zig");

fn sourceFilter(name: []const u8, parent_path: []const u8, kind: tar.Kind) tar.FilterResult {
    // if (std.mem.startsWith(u8, name, ".")) return .Skip;

    if (std.mem.eql(u8, parent_path, "./")) { // Root directory
        if (std.mem.eql(u8, name, "assets")) return .Skip;
        if (std.mem.eql(u8, name, "boot")) return .Skip;
    }

    switch (kind) {
        .Directory => {
            // Skip zig cache and output dirs everywhere
            if (std.mem.eql(u8, name, "zig-cache")) return .Skip;
            if (std.mem.eql(u8, name, "zig-out")) return .Skip;

            // Skip git directories everywhere
            if (std.mem.eql(u8, name, ".git")) return .Skip;
        },
        .File => {},
        else => {},
    }

    return .Include;
}

fn makeSourceBlob(_: *std.build.Step) anyerror!void {
    const dirname = std.fs.path.dirname(source_blob_path).?;
    std.fs.cwd().makePath(dirname) catch unreachable;
    try tar.create(".", source_blob_path, sourceFilter);
}

fn prepareSourceBlobStep(b: *std.build.Builder, exec: *std.build.LibExeObjStep) void {
    if (source_blob_step == null) {
        source_blob_step = std.build.Step.init(.custom, "source blob", b.allocator, makeSourceBlob);
        source_blob_path = b.getInstallPath(.bin, "sources.tar");
        b.pushInstalledFile(.bin, "sources.tar");
    }
    exec.step.dependOn(&source_blob_step.?);
}

pub fn setTargetFlags(
    exec: *std.build.LibExeObjStep,
    arch: Arch,
    context: Context,
) void {
    var disabled_features = std.Target.Cpu.Feature.Set.empty;
    var enabled_feautres = std.Target.Cpu.Feature.Set.empty;

    switch (arch) {
        .x86_64 => {
            const features = std.Target.x86.Feature;
            if (context == .kernel) {
                // Disable SIMD registers
                disabled_features.addFeature(@enumToInt(features.mmx));
                disabled_features.addFeature(@enumToInt(features.sse));
                disabled_features.addFeature(@enumToInt(features.sse2));
                disabled_features.addFeature(@enumToInt(features.avx));
                disabled_features.addFeature(@enumToInt(features.avx2));

                enabled_feautres.addFeature(@enumToInt(features.soft_float));
                exec.code_model = .kernel;
            } else {
                exec.code_model = .small;
            }
        },
        .aarch64 => {
            const features = std.Target.aarch64.Feature;
            if (context == .kernel) {
                // This is equal to -mgeneral-regs-only
                disabled_features.addFeature(@enumToInt(features.fp_armv8));
                disabled_features.addFeature(@enumToInt(features.crypto));
                disabled_features.addFeature(@enumToInt(features.neon));
            }
            exec.code_model = .small;
        },
        .riscv64 => {
            // idfk
            exec.code_model = .small;
        },
        else => unreachable,
    }

    exec.disable_stack_probing = switch (context) {
        .kernel => true,
        .userspace => false,
    };

    exec.setTarget(.{
        .cpu_arch = arch,
        .os_tag = std.Target.Os.Tag.freestanding,
        .abi = std.Target.Abi.none,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_feautres,
    });
}

pub fn makeExec(params: struct {
    builder: *std.build.Builder,
    arch: Arch,
    ctx: Context,
    filename: []const u8,
    main: []const u8,
    source_blob: bool,
    mode: ?std.builtin.Mode = null,
    strip_symbols: bool = false,
}) !*std.build.LibExeObjStep {
    const mode = params.mode orelse params.builder.standardReleaseOptions();

    const exec = params.builder.addExecutable(params.filename, params.main);
    setTargetFlags(exec, params.arch, params.ctx);
    exec.setBuildMode(mode);
    exec.strip = params.strip_symbols;

    // https://github.com/ziglang/zig/issues/10364
    if (@hasField(@TypeOf(exec.*), "want_lto"))
        exec.want_lto = false;

    if (params.source_blob) {
        prepareSourceBlobStep(params.builder, exec);
    }

    try @import("../lib/build.zig").add(
        params.builder,
        exec,
        if (params.source_blob) source_blob_path else null,
    );
    exec.addPackagePath("config", "./config/config.zig");
    exec.addPackagePath("assets", "./assets/assets.zig");

    exec.setMainPkgPath(".");
    exec.setOutputDir(params.builder.cache_root);
    exec.install();
    return exec;
}
