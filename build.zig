const std = @import("std");
const Builder = std.build.Builder;
const builtin = std.builtin;
const assert = std.debug.assert;

const Context = enum {
  kernel,
  userspace,
};

var source_blob: *std.build.RunStep = undefined;
var source_blob_path: []u8 = undefined;

fn make_source_blob(b: *Builder) void {
  source_blob_path =
    std.mem.concat(b.allocator, u8,
      &[_][]const u8{ b.cache_root, "/sources.tar" }
    ) catch unreachable;

  source_blob = b.addSystemCommand(
    &[_][]const u8 {
      "tar", "--no-xattrs", "-cf", source_blob_path, "src", "build.zig",
    },
  );
}

fn target(arch: builtin.Arch, context: Context) std.zig.CrossTarget {
  var disabled_features = std.Target.Cpu.Feature.Set.empty;
  var enabled_feautres  = std.Target.Cpu.Feature.Set.empty;

  if(arch == .aarch64) { // This is equal to -mgeneral-regs-only
    const features = std.Target.aarch64.Feature;
    disabled_features.addFeature(@enumToInt(features.fp_armv8));
    disabled_features.addFeature(@enumToInt(features.crypto));
    disabled_features.addFeature(@enumToInt(features.neon));
  }

  if(arch == .x86_64) {
    const features = std.Target.x86.Feature;
    // Disable SIMD registers
    disabled_features.addFeature(@enumToInt(features.mmx));
    disabled_features.addFeature(@enumToInt(features.sse));
    disabled_features.addFeature(@enumToInt(features.sse2));
    disabled_features.addFeature(@enumToInt(features.avx));
    disabled_features.addFeature(@enumToInt(features.avx2));

    enabled_feautres.addFeature(@enumToInt(features.soft_float));
  }

  return std.zig.CrossTarget {
    .cpu_arch = arch,
    .os_tag = std.Target.Os.Tag.freestanding,
    .abi = std.Target.Abi.none,
    .cpu_features_sub = disabled_features,
    .cpu_features_add = enabled_feautres,
  };
}

fn build_kernel(b: *Builder, arch: builtin.Arch, main: []const u8, name: []const u8, asmfiles: [][]const u8) *std.build.LibExeObjStep {
  const kernel_filename =
    std.mem.concat(b.allocator, u8,
      &[_][]const u8{ "Zigger_", name, "_", @tagName(arch) }
    ) catch unreachable;

  const kernel = b.addExecutable(kernel_filename, main);
  kernel.addBuildOption([] const u8, "source_blob_path", std.mem.concat(b.allocator, u8, &[_][]const u8{ "../../", source_blob_path } ) catch unreachable);
  kernel.setTarget(target(arch, .kernel));
  kernel.setBuildMode(.ReleaseSmall);
  kernel.setLinkerScriptPath("src/kernel/kernel.ld");

  for(asmfiles) |f| {
    kernel.addAssemblyFile(f);
  }

  switch(arch) {
    .x86_64 => {
      //kernel.addAssemblyFile("src/platform/x86_64/ap_boot.asm");
      kernel.code_model = .kernel;
    },
    .aarch64 => {

    },
    else => { }
  }

  kernel.setMainPkgPath("src/");
  kernel.setOutputDir(b.cache_root);

  kernel.disable_stack_probing = true;

  kernel.install();

  kernel.step.dependOn(&source_blob.step);

  return kernel;
}

fn stivale_kernel(b: *Builder, arch: builtin.Arch) *std.build.LibExeObjStep {
  return build_kernel(b, arch, "src/boot/stivale.zig", "stivale",
    &[_][]u8 {
      std.mem.concat(b.allocator, u8,
        &[_][]const u8{ "src/boot/stivale_", @tagName(arch), ".asm" }
      ) catch unreachable
    }
  );
}

fn stivale2_kernel(b: *Builder, arch: builtin.Arch) *std.build.LibExeObjStep {
  return build_kernel(b, arch, "src/boot/stivale2.zig", "stivale2",
    &[_][]u8 {
      std.mem.concat(b.allocator, u8,
        &[_][]const u8{ "src/boot/stivale2_", @tagName(arch), ".asm" }
      ) catch unreachable
    }
  );
}

fn qemu_run_aarch64_sabaton(b: *Builder, board_name: []const u8, desc: []const u8, dep: *std.build.LibExeObjStep) void {
  const command_step = b.step(board_name, desc);

  const params =
    &[_][]const u8 {
      "qemu-system-aarch64",
      "-M", board_name,
      "-cpu", "cortex-a57",
      "-drive", "if=pflash,format=raw,file=Sabaton/out/virt.bin,readonly=on",
      "-drive",
      std.mem.concat(b.allocator, u8, &[_][]const u8{
        "if=pflash,format=raw,file=", dep.getOutputPath(), ",readonly=on"
      }) catch unreachable,
      "-m", "4G",
      "-serial", "stdio",
      //"-S", "-s",
      //"-d", "int",
    };

  const pad_step = b.addSystemCommand(
    &[_][]const u8 {
      "truncate", "-s", "64M", dep.getOutputPath(),
    },
  );

  const run_step = b.addSystemCommand(params);
  pad_step.step.dependOn(&dep.step);
  run_step.step.dependOn(&pad_step.step);
  command_step.dependOn(&run_step.step);
}

fn qemu_run_image_x86_64(b: *Builder, image_path: []const u8) *std.build.RunStep {
  const run_params =
    &[_][]const u8 {
      "qemu-system-x86_64",
      "-drive",
      std.mem.concat(b.allocator, u8, &[_][]const u8{ "format=raw,file=", image_path }) catch unreachable,
      "-debugcon", "stdio",
      "-m", "4G",
      "-no-reboot",
      "-machine", "q35",
      "-device", "qemu-xhci",
      "-smp", "8",
      //"-cpu", "host", "-enable-kvm",
      //"-d", "int",
      //"-s", "-S",
    };
  return b.addSystemCommand(run_params);
}

fn echfs_image(b: *Builder, image_path: []const u8, kernel_path: []const u8, install_command: []const u8) *std.build.RunStep {
  const image_params =
    &[_][]const u8 {
      "/bin/sh", "-c",
      std.mem.concat(b.allocator, u8, &[_][]const u8{
        "rm ", image_path, " || true && ",
        "dd if=/dev/zero bs=1048576 count=0 seek=4 of=", image_path, " && ",
        "parted -s ", image_path, " mklabel msdos && ",
        "parted -s ", image_path, " mkpart primary 1 100% && ",
        "parted -s ", image_path, " set 1 boot on && ",
        "echfs-utils -m -p0 ", image_path, " quick-format 32768 && ",
        "echfs-utils -m -p0 ", image_path, " import '", kernel_path, "' Zigger.elf && ",
        install_command,
      }) catch unreachable,
    };
  return b.addSystemCommand(image_params);
}

fn qloader_target(b: *Builder, command: []const u8, desc: []const u8, image_path: []const u8, dep: *std.build.LibExeObjStep) void {
  assert(dep.target.cpu_arch.? == .x86_64);

  const command_step = b.step(command, desc);
  const run_step = qemu_run_image_x86_64(b, image_path);
  const image_step = echfs_image(b, image_path, dep.getOutputPath(),
    std.mem.concat(b.allocator, u8, &[_][]const u8{
      "echfs-utils -m -p0 ", image_path, " import qloader_image/qloader2.cfg qloader2.cfg && ",
      "./qloader2/qloader2-install ./qloader2/qloader2.bin ", image_path
    }) catch unreachable);

  image_step.step.dependOn(&dep.step);
  run_step.step.dependOn(&image_step.step);
  command_step.dependOn(&run_step.step);
}

fn limine_target(b: *Builder, command: []const u8, desc: []const u8, image_path: []const u8, dep: *std.build.LibExeObjStep) void {
  assert(dep.target.cpu_arch.? == .x86_64);

  const command_step = b.step(command, desc);
  const run_step = qemu_run_image_x86_64(b, image_path);
  const image_step = echfs_image(b, image_path, dep.getOutputPath(),
    std.mem.concat(b.allocator, u8, &[_][]const u8{
      "make -C limine limine-install && ",
      "echfs-utils -m -p0 ", image_path, " import limine_image/limine.cfg limine.cfg && ",
      "./limine/limine-install ./limine/limine.bin ", image_path
    }) catch unreachable);

  image_step.step.dependOn(&dep.step);
  run_step.step.dependOn(&image_step.step);
  command_step.dependOn(&run_step.step);
}

pub fn build(b: *Builder) void {
  const sources = make_source_blob(b);

  qemu_run_aarch64_sabaton(b,
    "virt",
    "Run aarch64 kernel with Sabaton stivale2 on the virt board",
    stivale2_kernel(b, builtin.Arch.aarch64),
  );
  //_ = stivale2_kernel(b, builtin.Arch.riscv64);

  qloader_target(
    b,
    "ql2",
    "Run x86_64 kernel with qloader2 stivale",
    std.mem.concat(b.allocator, u8,
      &[_][]const u8{
        b.cache_root,
        "/ql2.img",
      }) catch unreachable,
    stivale_kernel(b, builtin.Arch.x86_64)
  );

  limine_target(
    b,
    "limine",
    "Run x86_64 kernel with limine stivale2",
    std.mem.concat(b.allocator, u8,
      &[_][]const u8{
        b.cache_root,
        "/limine.img",
      }) catch unreachable,
    stivale2_kernel(b, builtin.Arch.x86_64)
  );
}
