const std = @import("std");
const Builder = std.build.Builder;
const builtin = std.builtin;
const assert = std.debug.assert;

const sabaton = @import("boot/Sabaton/build.zig");

const Context = enum {
    kernel,
    blobspace,
    userspace,
};

var source_blob: *std.build.RunStep = undefined;
var source_blob_path: []u8 = undefined;

fn make_source_blob(b: *Builder) void {
    source_blob_path = b.fmt("{s}/sources.tar", .{b.cache_root});

    source_blob = b.addSystemCommand(
        &[_][]const u8{
            "tar", "--no-xattrs", "-cf", source_blob_path, "src", "build.zig",
        },
    );
}

fn target(exec: *std.build.LibExeObjStep, arch: builtin.Arch, context: Context) void {
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
        .blobspace => true,
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

fn add_libs(exec: *std.build.LibExeObjStep) void {
}

fn make_exec(b: *Builder, arch: builtin.Arch, ctx: Context, filename: []const u8, main: []const u8) *std.build.LibExeObjStep {
    const exec = b.addExecutable(filename, main);
    exec.addBuildOption([]const u8, "source_blob_path", b.fmt("../../{s}", .{source_blob_path}));
    target(exec, arch, ctx);
    add_libs(exec);
    exec.setBuildMode(.ReleaseSafe);
    exec.strip = false;
    exec.setMainPkgPath("src/");
    exec.setOutputDir(b.cache_root);

    exec.install();

    exec.step.dependOn(&source_blob.step);

    return exec;
}

fn build_kernel(b: *Builder, arch: builtin.Arch, name: []const u8) *std.build.LibExeObjStep {
    const kernel_filename = b.fmt("Flork_{s}_{s}", .{ name, @tagName(arch) });
    const main_file = b.fmt("src/boot/{s}.zig", .{name});

    const kernel = make_exec(b, arch, .kernel, kernel_filename, main_file);
    kernel.addAssemblyFile(b.fmt("src/boot/{s}_{s}.asm", .{ name, @tagName(arch) }));
    kernel.setLinkerScriptPath("src/kernel/kernel.ld");

    //kernel.step.dependOn(&build_dyld(b, arch).step);

    return kernel;
}

fn build_dyld(b: *Builder, arch: builtin.Arch) *std.build.LibExeObjStep {
    const dyld_filename = b.fmt("Dyld_", .{@tagName(arch)});

    const dyld = make_exec(b, arch, .blobspace, dyld_filename, "src/userspace/dyld/dyld.zig");
    dyld.setLinkerScriptPath("src/userspace/dyld/dyld.ld");

    return dyld;
}

fn qemu_run_aarch64_sabaton(b: *Builder, board_name: []const u8, desc: []const u8) !void {
    const sabaton_blob = try sabaton.build_blob(b, .aarch64, board_name, "boot/Sabaton/");

    const flork = build_kernel(b, .aarch64, "stivale2");
    const flork_blob = try sabaton.pad_file(b, &flork.step, flork.getOutputPath());

    const command_step = b.step(board_name, desc);

    const params = &[_][]const u8 {
        "qemu-system-aarch64",
        "-M", board_name, 
        "-cpu", "cortex-a57",
        "-drive", b.fmt("if=pflash,format=raw,file={s},readonly=on", .{sabaton_blob.output_path}),
        "-drive", b.fmt("if=pflash,format=raw,file={s},readonly=on", .{flork_blob.output_path}),
        "-m", "4G",
        "-serial", "stdio",
        //"-S", "-s",
        "-d", "int",
        "-smp", "4",
        "-device", "ramfb",
    };

    const run_step = b.addSystemCommand(params);
    run_step.step.dependOn(&sabaton_blob.step);
    run_step.step.dependOn(&flork_blob.step);
    command_step.dependOn(&run_step.step);
}

fn qemu_run_riscv_sabaton(b: *Builder, board_name: []const u8, desc: []const u8, dep: *std.build.LibExeObjStep) void {
    const command_step = b.step(board_name, desc);

    const params = &[_][]const u8{
        "qemu-system-riscv64",
        "-M", board_name,
        "-cpu", "rv64",
        "-drive", b.fmt("if=pflash,format=raw,file=Sabaton/out/riscv64_{s}.bin,readonly=on", .{board_name}),
        "-drive", b.fmt("if=pflash,format=raw,file={s},readonly=on", .{dep.getOutputPath()}),
        "-m", "4G",
        "-serial", "stdio",
        //"-S", "-s",
        "-d", "int",
        "-smp", "4",
        "-device", "virtio-gpu-pci",
    };

    const pad_step = b.addSystemCommand(
        &[_][]const u8{
            "truncate", "-s", "64M", dep.getOutputPath(),
        },
    );

    const run_step = b.addSystemCommand(params);
    pad_step.step.dependOn(&dep.step);
    run_step.step.dependOn(&pad_step.step);
    command_step.dependOn(&run_step.step);
}

fn qemu_run_image_x86_64(b: *Builder, image_path: []const u8) *std.build.RunStep {
    const run_params = &[_][]const u8{
        "qemu-system-x86_64",
        "-drive", b.fmt("format=raw,file={s}", .{image_path}),
        "-debugcon", "stdio",
        "-vga", "virtio",
        //"-serial", "stdio",
        "-m", "4G",
        "-display", "gtk,zoom-to-fit=off",
        "-no-reboot",
        "-no-shutdown",
        "-machine", "q35",
        "-device", "qemu-xhci",
        "-smp", "8",
        //"-cpu", "host", "-enable-kvm",
        //"-d", "int",
        //"-s", "-S",
        //"-trace", "ahci_*",
    };
    return b.addSystemCommand(run_params);
}

fn echfs_image(b: *Builder, image_path: []const u8, kernel_path: []const u8, install_command: []const u8) *std.build.RunStep {
    const image_params = &[_][]const u8{
        "/bin/sh", "-c",
        std.mem.concat(b.allocator, u8, &[_][]const u8{
            "make -C boot/echfs && ",
            "rm ", image_path, " || true && ",
            "dd if=/dev/zero bs=1048576 count=0 seek=8 of=", image_path, " && ",
            "parted -s ", image_path, " mklabel msdos && ",
            "parted -s ", image_path, " mkpart primary 1 100% && ",
            "parted -s ", image_path, " set 1 boot on && ",
            "./boot/echfs/echfs-utils -m -p0 ", image_path, " quick-format 32768 && ",
            "./boot/echfs/echfs-utils -m -p0 ", image_path, " import '", kernel_path, "' flork.elf && ",
            install_command,
        }) catch unreachable,
    };
    return b.addSystemCommand(image_params);
}

fn limine_target(b: *Builder, command: []const u8, desc: []const u8, image_path: []const u8, root_path: []const u8, dep: *std.build.LibExeObjStep) void {
    assert(dep.target.cpu_arch.? == .x86_64);

    const command_step = b.step(command, desc);
    const run_step = qemu_run_image_x86_64(b, image_path);
    const image_step = echfs_image(b, image_path, dep.getOutputPath(), std.mem.concat(b.allocator, u8, &[_][]const u8{
        "make -C boot/limine limine-install && ",
        "make -C boot/echfs && ",
        "./boot/echfs/echfs-utils -m -p0 ", image_path, " import ", root_path, "/limine.cfg limine.cfg && ",
        "./boot/limine/limine-install ",
        image_path,
    }) catch unreachable);

    image_step.step.dependOn(&dep.step);
    run_step.step.dependOn(&image_step.step);
    command_step.dependOn(&run_step.step);
}

pub fn build(b: *Builder) !void {
    const sources = make_source_blob(b);

    // try qemu_run_aarch64_sabaton(
    //     b,
    //     "raspi3",
    //     "(WIP) Run aarch64 kernel with Sabaton stivale2 on the raspi3 board",
    // );

    try qemu_run_aarch64_sabaton(
        b,
        "virt",
        "Run aarch64 kernel with Sabaton stivale2 on the virt board",
    );

    // qemu_run_riscv_sabaton(b,
    //   "riscv-virt",
    //   "(WIP) Run risc-v kernel with Sabaton stivale2 on the virt board",
    //   build_kernel(b, builtin.Arch.riscv64, "stivale2"),
    // );

    limine_target(
        b,
        "x86_64-stivale2",
        "Run x86_64 kernel with limine stivale2",
        b.fmt("{s}/stivale2.img", .{b.cache_root}),
        "boot/stivale2_image",
        build_kernel(b, builtin.Arch.x86_64, "stivale2"),
    );
}
