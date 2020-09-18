const std = @import("std");
const Builder = std.build.Builder;
const builtin = std.builtin;
const assert = std.debug.assert;

const Context = enum {
  kernel,
  userspace,
};

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

fn build_kernel(b: *Builder, arch: builtin.Arch, board_name: ?[]const u8, main: []const u8, name: []const u8, asmfiles: [][]const u8) *std.build.LibExeObjStep {
  const kernel_filename =
    std.mem.concat(b.allocator, u8,
      &[_][]const u8{ "Zigger_", name, if(board_name==null) "" else "_", if(board_name==null) "" else board_name.?, "_", @tagName(arch) }
    ) catch unreachable;

  const kernel = b.addExecutable(kernel_filename, main);
  kernel.setTarget(target(arch, .kernel));
  kernel.setLinkerScriptPath("src/linker.ld");
  //kernel.code_model = .large;
  kernel.setBuildMode(.ReleaseSafe);

  for(asmfiles) |f| {
    kernel.addAssemblyFile(f);
  }

  kernel.setMainPkgPath("src/");
  kernel.setOutputDir(b.cache_root);
  kernel.install();

  return kernel;
}

fn stivale_kernel(b: *Builder, arch: builtin.Arch) *std.build.LibExeObjStep {
  return build_kernel(b, arch, null, "src/boot/stivale.zig", "stivale",
    &[_][]u8 {
      std.mem.concat(b.allocator, u8,
        &[_][]const u8{ "src/boot/stivale_", @tagName(arch), ".asm" }
      ) catch unreachable
    }
  );
}

fn baremetal_kernel(b: *Builder, board_name: []const u8, arch: builtin.Arch) *std.build.LibExeObjStep {
  return build_kernel(b, arch, board_name,
    std.mem.concat(b.allocator, u8,
      &[_][]const u8{"src/boot/baremetal_", board_name, ".zig" }
    ) catch unreachable, "baremetal",
    &[_][]u8 {
      std.mem.concat(b.allocator, u8,
        &[_][]const u8{ "src/boot/baremetal_", board_name, "_", @tagName(arch), ".asm" }
      ) catch unreachable
    }
  );
}

fn qemu_aarch64_baremetal_target(b: *Builder, board_name: []const u8, desc: []const u8, dep: *std.build.LibExeObjStep) void {
  const command_step = b.step(board_name, desc);

  const params =
    switch(dep.target.cpu_arch.?) {
      builtin.Arch.aarch64 => &[_][]const u8 {
        "qemu-system-aarch64",
        "-M", board_name,
        "-cpu", "cortex-a57",
        "-kernel", dep.getOutputPath(),
        "-m", "4G",
        "-serial", "stdio",
        //"-S", "-s",
        "-d", "int",
      },
      else => unreachable,
    };

  const run_step = b.addSystemCommand(params);
  run_step.step.dependOn(&dep.step);

  command_step.dependOn(&run_step.step);
}

fn qloader_target(b: *Builder, command: []const u8, desc: []const u8, image_path: []const u8, dep: *std.build.LibExeObjStep) void {
  assert(dep.target.cpu_arch.? == .x86_64);

  const command_step = b.step(command, desc);

  const run_params =
    &[_][]const u8 {
      "qemu-system-x86_64",
      "-drive",
      std.mem.concat(b.allocator, u8,
        &[_][]const u8{ "format=raw,file=", image_path }
      ) catch unreachable,
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
  const run_step = b.addSystemCommand(run_params);

  const image_params =
    &[_][]const u8 {
      "/bin/sh", "-c",
      std.mem.concat(b.allocator, u8,
        &[_][]const u8{
          "rm ", image_path, " || true && ",
          "dd if=/dev/zero bs=1M count=0 seek=4 of=", image_path, " && ",
          "parted -s ", image_path, " mklabel msdos && ",
          "parted -s ", image_path, " mkpart primary 1 100% && ",
          "parted -s ", image_path, " set 1 boot on && ",
          "echfs-utils -m -p0 ", image_path, " quick-format 32768 && ",
          "echfs-utils -m -p0 ", image_path, " import qloader_image/qloader2.cfg qloader2.cfg && ",
          "echfs-utils -m -p0 ", image_path, " import ", dep.getOutputPath(), " Zigger.elf && ",
          "./qloader2/qloader2-install ./qloader2/qloader2.bin ", image_path,
        }
      ) catch unreachable
    };
  const image_step = b.addSystemCommand(image_params);

  image_step.step.dependOn(&dep.step);
  run_step.step.dependOn(&image_step.step);
  command_step.dependOn(&run_step.step);
}

pub fn build(b: *Builder) void {
  _ = stivale_kernel(b, builtin.Arch.aarch64);
  //_ = stivale_kernel(b, builtin.Arch.riscv64);

  qemu_aarch64_baremetal_target(b, "virt", "Run aarch64 bare metal virt board kernel in qemu", baremetal_kernel(b, "virt", builtin.Arch.aarch64));
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
}
