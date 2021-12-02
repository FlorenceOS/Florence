const std = @import("std");
const Builder = std.build.Builder;
const builtin = std.builtin;
const assert = std.debug.assert;

const sabaton = @import("boot/Sabaton/build.zig");
const flork = @import("subprojects/flork/build.zig");

// zig fmt: off
fn qemu_run_aarch64_sabaton(b: *Builder, board_name: []const u8, desc: []const u8) !void {
    const sabaton_blob = try sabaton.build_blob(b, .aarch64, board_name);

    const kernel_step = try flork.buildKernel(.{
        .builder = b, 
        .arch = .aarch64,
    });

    const kernel_path = b.getInstallPath(kernel_step.install_step.?.dest_dir, kernel_step.out_filename);

    const command_step = b.step(board_name, desc);

    const params = &[_][]const u8 {
        "qemu-system-aarch64",
        "-M", board_name, 
        "-cpu", "cortex-a57",
        "-drive", b.fmt("if=pflash,format=raw,file={s},readonly=on", .{sabaton_blob.output_path}),
        "-fw_cfg", b.fmt("opt/Sabaton/kernel,file={s}", .{kernel_path}),
        "-m", "4G",
        "-serial", "stdio",
        //"-S", "-s",
        "-smp", "4",
        "-device", "virtio-gpu-pci",
        "-device", "ramfb",
    };

    const run_step = b.addSystemCommand(params);
    run_step.step.dependOn(&sabaton_blob.step);
    run_step.step.dependOn(&kernel_step.install_step.?.step);
    command_step.dependOn(&run_step.step);
}

fn qemu_run_riscv_sabaton(b: *Builder, board_name: []const u8, desc: []const u8, dep: *std.build.LibExeObjStep) void {
    const command_step = b.step(board_name, desc);

    const kernel_path = b.getInstallPath(dep.install_step.?.dest_dir, dep.out_filename);

    const params = &[_][]const u8{
        "qemu-system-riscv64",
        "-M", board_name,
        "-cpu", "rv64",
        "-drive", b.fmt("if=pflash,format=raw,file=Sabaton/out/riscv64_{s}.bin,readonly=on", .{board_name}),
        "-drive", b.fmt("if=pflash,format=raw,file={s},readonly=on", .{kernel_path}),
        "-m", "4G",
        "-serial", "stdio",
        //"-S", "-s",
        "-d", "int",
        "-smp", "4",
        "-device", "virtio-gpu-pci",
    };

    const pad_step = b.addSystemCommand(
        &[_][]const u8{
            "truncate", "-s", "64M", kernel_path,
        },
    );

    const run_step = b.addSystemCommand(params);
    pad_step.step.dependOn(&dep.install_step.?.step);
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
        "-no-reboot",
        "-no-shutdown",
        "-machine", "q35,accel=kvm:whpx:tcg",
        "-device", "qemu-xhci",
        "-netdev", "user,id=mynet0",
        "-device", "e1000,netdev=mynet0",
        "-smp", "8",
        //"-d", "int",
        //"-s", "-S",
        //"-trace", "ahci_*",
    };
    return b.addSystemCommand(run_params);
}

fn universal_x86_64_image(b: *Builder, image_path: []const u8, kernel_path: []const u8) *std.build.RunStep {
    const image_dir = b.fmt("./{s}/universal_image/", .{b.cache_root});

    const image_params = &[_][]const u8{
        "/bin/sh", "-c",
        std.mem.concat(b.allocator, u8, &[_][]const u8{
            "make -C boot/limine-bin && ",
            "mkdir -p ", image_dir, " && ",
            "cp boot/stivale2_image/limine.cfg ",
              "boot/limine-bin/limine.sys ", "boot/limine-bin/limine-cd.bin ",
              "boot/limine-bin/limine-eltorito-efi.bin ",
            image_dir, " && ",
            "cp ", kernel_path, " ", image_dir, "/flork.elf && ",
            "xorriso -as mkisofs -b limine-cd.bin ",
                "-no-emul-boot -boot-load-size 4 -boot-info-table ",
                "--efi-boot limine-eltorito-efi.bin ",
                "-efi-boot-part --efi-boot-image --protective-msdos-label ",
                image_dir, " -o ", image_path,
            "&&",
            "boot/limine-bin/limine-install ", image_path,
        }) catch unreachable,
    };
    return b.addSystemCommand(image_params);
}

fn limine_target(b: *Builder, command: []const u8, desc: []const u8, image_path: []const u8, dep: *std.build.LibExeObjStep) void {
    assert(dep.target.cpu_arch.? == .x86_64);

    const command_step = b.step(command, desc);
    const run_step = qemu_run_image_x86_64(b, image_path);

    const kernel_path = b.getInstallPath(dep.install_step.?.dest_dir, dep.out_filename);

    const image_step = universal_x86_64_image(b, image_path, kernel_path);

    image_step.step.dependOn(&dep.install_step.?.step);
    run_step.step.dependOn(&image_step.step);
    command_step.dependOn(&run_step.step);
}

// zig fmt: on
pub fn build(b: *Builder) !void {
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
        try flork.buildKernel(.{
            .builder = b,
            .arch = .x86_64,
        }),
    );
}
