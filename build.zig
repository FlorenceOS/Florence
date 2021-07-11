const std = @import("std");
const Builder = std.build.Builder;
const builtin = std.builtin;
const assert = std.debug.assert;

const sabaton = @import("boot/Sabaton/build.zig");
const flork = @import("subprojects/flork/build.zig");

// zig fmt: off
fn qemu_run_aarch64_sabaton(b: *Builder, board_name: []const u8, desc: []const u8) !void {
    const sabaton_blob = try sabaton.build_blob(b, .aarch64, board_name, "boot/Sabaton/");

    const kernel_step = flork.buildKernel(.{
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
        "-display", "gtk,zoom-to-fit=off",
    };

    const run_step = b.addSystemCommand(params);
    run_step.step.dependOn(&sabaton_blob.step);
    run_step.step.dependOn(&kernel_step.install_step.?.step);
    command_step.dependOn(&run_step.step);
}

fn qemu_run_riscv_sabaton(b: *Builder, board_name: []const u8, desc: []const u8, dep: *std.build.LibExeObjStep) void {
    const command_step = b.step(board_name, desc);

    const kernel_path = b.getInstallPath(kernel_stepdep.install_step.?.dest_dir, dep.out_filename);

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
        "-display", "gtk,zoom-to-fit=off",
        "-no-reboot",
        "-no-shutdown",
        "-machine", "q35",
        "-device", "qemu-xhci",
        "-smp", "8",
        "-cpu", "host", "-enable-kvm",
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
            "./boot/echfs/echfs-utils -m -p0 ", image_path, " import /usr/local/florence-limine/share/limine/limine.sys limine.sys && ",
            install_command,
        }) catch unreachable,
    };
    return b.addSystemCommand(image_params);
}

fn limine_target(b: *Builder, command: []const u8, desc: []const u8, image_path: []const u8, root_path: []const u8, dep: *std.build.LibExeObjStep) void {
    assert(dep.target.cpu_arch.? == .x86_64);

    const command_step = b.step(command, desc);
    const run_step = qemu_run_image_x86_64(b, image_path);

    const kernel_path = b.getInstallPath(dep.install_step.?.dest_dir, dep.out_filename);

    const image_step = echfs_image(b, image_path, kernel_path, std.mem.concat(b.allocator, u8, &[_][]const u8{
        "make -C boot/limine-bin install PREFIX=/usr/local/florence-limine/ && ",
        "make -C boot/echfs && ",
        "./boot/echfs/echfs-utils -m -p0 ", image_path, " import ", root_path, "/limine.cfg limine.cfg && ",
        "/usr/local/florence-limine/bin/limine-install ", image_path,
    }) catch unreachable);

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
        "boot/stivale2_image",
        flork.buildKernel(.{
            .builder = b, 
            .arch = .x86_64,
        }),
    );
}
