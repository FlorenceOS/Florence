const std = @import("std");

pub const Context = enum {
    kernel,
    userlib,
    userspace,
};

fn makeSourceBlobStep(
    b: *std.build.Builder,
    output: []const u8,
    src: []const u8,
) *std.build.RunStep {
    return b.addSystemCommand(
        &[_][]const u8{
            "tar", "--no-xattrs", "-cf", output, "lib", src, "build.zig",
        },
    );
}

pub fn setTargetFlags(
    exec: *std.build.LibExeObjStep,
    arch: std.builtin.Arch,
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
        .userlib => true,
        else => false,
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
    arch: std.builtin.Arch,
    ctx: Context,
    filename: []const u8,
    main: []const u8,
    source_blob: ?struct {
        global_source_path: []const u8,
        source_blob_name: []const u8,
    },
    mode: ?std.builtin.Mode = null,
}) *std.build.LibExeObjStep {
    const mode = params.mode orelse params.builder.standardReleaseOptions();

    const exec = params.builder.addExecutable(params.filename, params.main);
    setTargetFlags(exec, params.arch, params.ctx);
    exec.setBuildMode(mode);
    exec.strip = false;

    if (@hasField(@TypeOf(exec.*), "want_lto"))
        exec.want_lto = false;

    exec.setMainPkgPath(".");
    exec.setOutputDir(params.builder.cache_root);

    if (params.source_blob) |blob| {
        const cache_root = params.builder.cache_root;
        const source_blob_path = params.builder.fmt("{s}/{s}.tar", .{
            cache_root,
            blob.source_blob_name,
        });
        exec.addBuildOption([]const u8, "source_blob_path", source_blob_path);
        exec.step.dependOn(&makeSourceBlobStep(
            params.builder,
            source_blob_path,
            blob.global_source_path,
        ).step);
    }

    exec.install();
    return exec;
}
