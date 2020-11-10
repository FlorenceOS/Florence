const log = @import("../logger.zig").log;
const stivale = @import("stivale_common.zig");

const paging = @import("../paging.zig");
const vmm = @import("../vmm.zig");
const platform = @import("../platform.zig");
const kmain = @import("../kmain.zig").kmain;
const acpi = @import("../platform/acpi.zig");
const serial = @import("../serial.zig");
const vital = @import("../vital.zig").vital;

const vesa_log = @import("../drivers/vesa_log.zig");
const vga_log = @import("../drivers/vga_log.zig");

const MemmapEntry = stivale.MemmapEntry;

const std = @import("std");

const arch = @import("builtin").arch;

pub const os = @import("../os/kernel.zig");

const stivale2_tag = packed struct {
  identifier: u64,
  next: ?*stivale2_tag,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("Identifier: 0x{X:0>16}", .{self.identifier});
  }
};

const stivale2_info = packed struct {
  bootloader_brand: [64]u8,
  bootloader_version: [64]u8,
  tags: ?*stivale2_tag,
};

const stivale2_memmap = packed struct {
  tag: stivale2_tag,
  entries: u64,

  pub fn get(self: *const @This()) []MemmapEntry {
    return @intToPtr([*]MemmapEntry, @ptrToInt(&self.entries) + 8)[0..self.entries];
  }

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("{} entries:\n", .{self.entries});
    for(self.get()) |ent| {
      try writer.print("\t\t{}\n", .{ent});
    }
  }
};

const stivale2_commandline = packed struct {
  tag: stivale2_tag,
  commandline: [*:0]u8,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("{}", .{self.commandline});
  }
};

const stivale2_framebuffer = packed struct {
  tag: stivale2_tag,
  addr: u64,
  width: u16,
  height: u16,
  pitch: u16,
  bpp: u16,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("0x{X}, {}x{}, bpp={}, pitch={}", .{self.addr, self.width, self.height, self.bpp, self.pitch});
  }
};

const stivale2_rsdp = packed struct {
  tag: stivale2_tag,
  rsdp: u64,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("0x{X}", .{self.rsdp});
  }
};

const stivale2_smp = packed struct {
  tag: stivale2_tag,
  entries: u64,
  cpus: [*]stivale2_smp_info,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("{} CPU(s)", .{self.entries});
  }
};

const stivale2_smp_info = packed struct {
  acpi_proc_uid: u32,
  lapic_id: u32,
  target_stack: u64,
  goto_address: u64,
};

const stivale2_mmio32_uart = packed struct {
  tag: stivale2_tag,
  uart_addr: u64,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("0x{X}", .{self.uart_addr});
  }
};

const stivale2_dtb = packed struct {
  tag: stivale2_tag,
  addr: [*]u8,
  size: u64,

  pub fn slice(self: *const @This()) []u8 {
    return self.addr[0..self.size];
  }

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("0x{X} bytes at 0x{X}", .{self.size, @ptrToInt(self.addr)});
  }
};

const parsed_info = struct {
  memmap:      ?*stivale2_memmap = null,
  commandline: ?*stivale2_commandline = null,
  framebuffer: ?*stivale2_framebuffer = null,
  rsdp:        ?*stivale2_rsdp = null,
  smp:         ?*stivale2_smp = null,
  dtb:         ?*stivale2_dtb = null,
  uart:        ?*stivale2_mmio32_uart = null,

  pub fn valid(self: *const parsed_info) bool {
    if(self.memmap == null) return false;
    return true;
  }

  pub fn format(self: *const parsed_info, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print(
      \\Parsed stivale2 tags:
      \\  Memmap: {}
      \\  Commandline: {}
      \\  Framebuffer: {}
      \\  RSDP: {}
      \\  SMP: {}
      \\  DTB: {}
      \\  UART: {}
      \\
      , .{self.memmap, self.commandline, self.framebuffer, self.rsdp, self.smp, self.dtb, self.uart});
  }
};

export fn stivale2_main(info_in: *stivale2_info) noreturn {
  log("Stivale2: Boot!\n", .{});

  var info = parsed_info{};

  var tag = info_in.tags;
  while(tag != null): (tag = tag.?.next) {
    switch(tag.?.identifier) {
      0x2187f79e8612de07 => info.memmap      = @ptrCast(*stivale2_memmap, tag),
      0xe5e76a1b4597a781 => info.commandline = @ptrCast(*stivale2_commandline, tag),
      0x506461d2950408fa => info.framebuffer = @ptrCast(*stivale2_framebuffer, tag),
      0x9e1786930a375e78 => info.rsdp        = @ptrCast(*stivale2_rsdp, tag),
      0x34d1d96339647025 => info.smp         = @ptrCast(*stivale2_smp, tag),
      0xabb29bd49a2833fa => info.dtb         = @ptrCast(*stivale2_dtb, tag),
      0xb813f9b8dbc78797 => info.uart        = @ptrCast(*stivale2_mmio32_uart, tag),
      else => { log("Unknown stivale2 tag identifier: 0x{X:0>16}\n", .{tag.?.identifier}); }
    }
  }

  if(info.uart) |uart| {
    serial.register_mmio32_serial(uart.uart_addr);
    log("Stivale2: Registered UART\n", .{});
  }

  log("{}\n", .{info});

  platform.platform_early_init();

  if(!info.valid()) {
    @panic("Stivale2: Info not valid!");
  }

  if(info.dtb) |dtb| {
    vital(@import("../platform/devicetree.zig").parse_dt(dtb.slice()), "parsing devicetree blob");
    log("Stivale2: Parsed devicetree blob!\n", .{});
  }

  for(info.memmap.?.get()) |*ent| {
    stivale.add_memmap(ent);
  }

  var paging_root = vital(paging.bootstrap_kernel_paging(), "bootstrapping kernel paging");

  if(arch == .x86_64)
    stivale.map_bootloader_data(&paging_root);

  for(info.memmap.?.get()) |*ent| {
    stivale.map_phys(ent, &paging_root);
  }

  if(info.uart) |uart| {
    vital(paging.map_phys_size(uart.uart_addr, platform.page_sizes[0], paging.mmio()), "mapping UART");
  }

  vital(paging.finalize_kernel_paging(&paging_root), "finalizing kernel paging");

  vital(vmm.init(stivale.phys_high(info.memmap.?.get())), "initializing vmm");

  if(info.framebuffer) |fb| {
    vesa_log.register_fb(fb.addr, fb.pitch, fb.width, fb.height, fb.bpp);
  }
  else {
    vga_log.register();
  }

  if(info.rsdp != null) {
    acpi.register_rsdp(info.rsdp.?.rsdp);
  }

  kmain();
}
