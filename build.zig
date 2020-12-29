const Array = @import("std").ArrayList;
const Builder = @import("std").build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const kernel = buildKernel(b);
    //const bootstrapper = buildBootstrapper(b);
    //const bootsector = buildBootsector(b);
    //const kernelLoader = buildKernelLoader(b);

    //const diskImage = buildDiskImage(b);

    const goAction = b.step("go", "Run with QEMU");
    const kvmAction = b.step("kvm", "Run with QEMU + KVM");

    const qemu_params = [][]const u8 {
        "qemu-system-x86_64",
        "-m", "4G",
        "-no-reboot",
        "-debugcon", "stdio",
        "-drive", "format=raw,file=out/Disk.bin",
        "-machine", "q35",
    };

    const kvm_extras = [][]const u8 {
        "-cpu", "host",
        "-enable-kvm",
    };

    var kvm_params = Array([]const u8).init(b.allocator);
    for(qemu_params) |p| { kvm_params.append(p) catch unreachable; }
    for(kvm_extras)  |p| { kvm_params.append(p) catch unreachable; }

    const run_qemu = b.addCommand(".", b.env_map, qemu_params);
    const rum_kvm = b.addCommand(".", b.env_map, kvm_params.toSlice());

    run_qemu.dependOn(diskImage);
    run_kvm.dependOn(diskImage);
}

fn buildKernel(b: *Builder) []const u8 {
    const kernelFlags = [][]const u8 {
        "-std=c++2a",
        "-mno-redzone",
    };

    const kernel = b.addExecutable("Florence Kernel", null);
    kernel.addCSourceFile("build/Kernel/Kernel.cpp", kernelFlags);
}
