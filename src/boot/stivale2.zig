const std = @import("std");
pub const os = @import("../os.zig");

const stivale = @import("stivale_common.zig");

const paging = os.memory.paging;
const vmm    = os.memory.vmm;

const platform = os.platform;
const kmain    = os.kernel.kmain;

const mmio_serial = os.drivers.mmio_serial;
const vesa_log    = os.drivers.vesa_log;
const vga_log     = os.drivers.vga_log;

const MemmapEntry = stivale.MemmapEntry;

const arch = @import("builtin").arch;

const stivale2_tag = packed struct {
  identifier: u64,
  next: u64,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("Identifier: 0x{X:0>16}", .{self.identifier});
  }
};

const stivale2_info = packed struct {
  bootloader_brand: [64]u8,
  bootloader_version: [64]u8,
  tags: u64,
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
      try writer.print("    {}\n", .{ent});
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

const stivale2_mmio32_status_uart = packed struct {
  tag: stivale2_tag,
  uart_addr: u64,
  uart_status: u64,
  status_mask: u32,
  status_value: u32,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("0x{X}, 0x{X}, (val & 0x{X}) == 0x{X}", .{self.uart_addr, self.uart_status, self.status_mask, self.status_value});
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
  memmap:      ?os.platform.phys_ptr(*stivale2_memmap) = null,
  commandline: ?os.platform.phys_ptr(*stivale2_commandline) = null,
  framebuffer: ?os.platform.phys_ptr(*stivale2_framebuffer) = null,
  rsdp:        ?os.platform.phys_ptr(*stivale2_rsdp) = null,
  smp:         ?os.platform.phys_ptr(*stivale2_smp) = null,
  dtb:         ?os.platform.phys_ptr(*stivale2_dtb) = null,
  uart:        ?os.platform.phys_ptr(*stivale2_mmio32_uart) = null,
  uart_status: ?os.platform.phys_ptr(*stivale2_mmio32_status_uart) = null,

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
      \\  UART with status: {}
      \\
      \\
      , .{self.memmap, self.commandline, self.framebuffer, self.rsdp, self.smp, self.dtb, self.uart, self.uart_status});
  }
};

export fn stivale2_main(info_in: *stivale2_info) noreturn {
  os.log("Stivale2: Boot!\n", .{});

  var info = parsed_info{};

  var tag = os.platform.phys_ptr(?*stivale2_tag).init(info_in.tags);
  while(tag.get()) |t|: (tag.write(t.next))  {
    switch(t.identifier) {
      0x2187f79e8612de07 => info.memmap      = os.platform.phys_ptr_cast(*stivale2_memmap, tag),
      0xe5e76a1b4597a781 => info.commandline = os.platform.phys_ptr_cast(*stivale2_commandline, tag),
      0x506461d2950408fa => info.framebuffer = os.platform.phys_ptr_cast(*stivale2_framebuffer, tag),
      0x9e1786930a375e78 => info.rsdp        = os.platform.phys_ptr_cast(*stivale2_rsdp, tag),
      0x34d1d96339647025 => info.smp         = os.platform.phys_ptr_cast(*stivale2_smp, tag),
      0xabb29bd49a2833fa => info.dtb         = os.platform.phys_ptr_cast(*stivale2_dtb, tag),
      0xb813f9b8dbc78797 => info.uart        = os.platform.phys_ptr_cast(*stivale2_mmio32_uart, tag),
      0xf77485dbfeb260f9 => info.uart_status = os.platform.phys_ptr_cast(*stivale2_mmio32_status_uart, tag),
      else => { os.log("Unknown stivale2 tag identifier: 0x{X:0>16}\n", .{t.identifier}); }
    }
  }

  if(info.uart) |uart| {
    mmio_serial.register_mmio32_serial(uart.get().uart_addr);
    os.log("Stivale2: Registered UART\n", .{});
  }

  if(info.uart_status) |u_| {
    const u = u_.get();
    mmio_serial.register_mmio32_status_serial(u.uart_addr, u.uart_status, u.status_mask, u.status_value);
    os.log("Stivale2: Registered status UART\n", .{});
  }

  platform.platform_early_init();

  os.log(
    \\Bootloader: {}
    \\Bootloader version: {}
    \\{}
    , .{info_in.bootloader_brand, info_in.bootloader_version, info}
  );

  if(!info.valid()) {
    @panic("Stivale2: Info not valid!");
  }

  if(info.dtb) |dtb| {
    os.vital(platform.devicetree.parse_dt(dtb.get().slice()), "parsing devicetree blob");
    os.log("Stivale2: Parsed devicetree blob!\n", .{});
  }

  for(info.memmap.?.get().get()) |*ent| {
    stivale.add_memmap(ent);
  }

  var paging_root = os.vital(paging.bootstrap_kernel_paging(), "bootstrapping kernel paging");

  if(arch == .x86_64)
    stivale.map_bootloader_data(&paging_root);

  for(info.memmap.?.get().get()) |*ent| {
    stivale.map_phys(ent, &paging_root);
  }

  if(info.uart) |uart| {
    os.log("Mapping UART\n", .{});
    os.vital(paging.map_phys_size(uart.get().uart_addr, platform.page_sizes[0], paging.mmio(), &paging_root), "mapping UART");
  }

  os.vital(paging.finalize_kernel_paging(&paging_root), "finalizing kernel paging");

  os.log("Doing vmm\n", .{});

  os.vital(vmm.init(stivale.phys_high(info.memmap.?.get().get())), "initializing vmm");

  os.log("Doing framebuffer\n", .{});

  if(info.framebuffer) |fb_| {
    const fb = fb_.get();
    vesa_log.register_fb(fb.addr, fb.pitch, fb.width, fb.height, fb.bpp);
  }
  else {
    vga_log.register();
  }

  if(info.rsdp) |rsdp| {
    os.log("Registering rsdp!\n", .{});
    platform.acpi.register_rsdp(rsdp.get().rsdp);
  }

  os.vital(os.platform.platform_init(), "calling platform_init");

  kmain();
}
