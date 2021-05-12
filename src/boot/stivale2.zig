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
const page_size   = os.platform.paging.page_sizes[0];

const MemmapEntry = stivale.MemmapEntry;

const arch = @import("builtin").arch;

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
      try writer.print("    {}\n", .{ent});
    }
  }
};

const stivale2_commandline = packed struct {
  tag: stivale2_tag,
  commandline: [*:0]u8,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("Commandline: {s}", .{self.commandline});
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
  flags: u64,
  bsp_lapic_id: u32,
  _: u32,
  entries: u64,

  pub fn format(self: *const @This(), fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("{} CPU(s): {}", .{self.entries, self.get()});
  }

  pub fn get(self: *const @This()) []stivale2_smp_info {
    return @intToPtr([*]stivale2_smp_info, @ptrToInt(&self.entries) + 8)[0..self.entries];
  }
};

const stivale2_smp_info = extern struct {
  acpi_proc_uid: u32,
  lapic_id: u32,
  target_stack: u64,
  goto_address: u64,
  argument: u64,
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
  memmap:      ?*stivale2_memmap = null,
  framebuffer: ?stivale2_framebuffer = null,
  rsdp:        ?u64 = null,
  smp:         ?os.platform.phys_ptr(*stivale2_smp) = null,
  dtb:         ?stivale2_dtb = null,
  uart:        ?stivale2_mmio32_uart = null,
  uart_status: ?stivale2_mmio32_status_uart = null,

  pub fn valid(self: *const parsed_info) bool {
    if(self.memmap == null) return false;
    return true;
  }

  pub fn format(self: *const parsed_info, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print(
      \\Parsed stivale2 tags:
      \\  Memmap: {}
      \\  Framebuffer: {}
      \\  RSDP: {}
      \\  SMP: {}
      \\  DTB: {}
      \\  UART: {}
      \\  UART with status: {}
      \\
      \\
      , .{self.memmap, self.framebuffer, self.rsdp, self.smp, self.dtb, self.uart, self.uart_status});
  }
};

fn smp_entry(info_in: u64) callconv(.C) noreturn {
  const smp_info = os.platform.phys_ptr(*stivale2_smp_info).from_int(info_in);
  const core_id = smp_info.get_writeback().argument;

  const cpu = &os.platform.smp.cpus[core_id];
  os.platform.thread.set_current_cpu(cpu);

  cpu.booted = true;
  platform.ap_init();
}

export fn stivale2_main(info_in: *stivale2_info) noreturn {
  platform.platform_early_init();
  
  os.log("Stivale2: Boot!\n", .{});

  var info = parsed_info{};

  var tag = info_in.tags;
  while(tag != null): (tag = tag.?.next) {
    switch(tag.?.identifier) {
      0x2187f79e8612de07 => info.memmap      = @ptrCast(*stivale2_memmap, tag),
      0xe5e76a1b4597a781 => os.log("{s}\n",  .{@ptrCast(*stivale2_commandline, tag)}),
      0x506461d2950408fa => info.framebuffer = @ptrCast(*stivale2_framebuffer, tag).*,
      0x9e1786930a375e78 => info.rsdp        = @ptrCast(*stivale2_rsdp, tag).rsdp,
      0x34d1d96339647025 => info.smp         = os.platform.phys_ptr(*stivale2_smp).from_int(@ptrToInt(tag)),
      0xabb29bd49a2833fa => info.dtb         = @ptrCast(*stivale2_dtb, tag).*,
      0xb813f9b8dbc78797 => info.uart        = @ptrCast(*stivale2_mmio32_uart, tag).*,
      0xf77485dbfeb260f9 => info.uart_status = @ptrCast(*stivale2_mmio32_status_uart, tag).*,
      else => { os.log("Unknown stivale2 tag identifier: 0x{X:0>16}\n", .{tag.?.identifier}); }
    }
  }

  stivale.detect_phys_base();

  if(info.uart) |uart| {
    mmio_serial.register_mmio32_serial(uart.uart_addr);
    os.log("Stivale2: Registered UART\n", .{});
  }

  if(info.uart_status) |u| {
    mmio_serial.register_mmio32_status_serial(u.uart_addr, u.uart_status, u.status_mask, u.status_value);
    os.log("Stivale2: Registered status UART\n", .{});
  }

  os.memory.pmm.init();

  os.log(
    \\Bootloader: {s}
    \\Bootloader version: {s}
    \\{}
    , .{info_in.bootloader_brand, info_in.bootloader_version, info}
  );

  if(!info.valid()) {
    @panic("Stivale2: Info not valid!");
  }

  if(info.dtb) |dtb| {
    os.vital(platform.devicetree.parse_dt(dtb.slice()), "parsing devicetree blob");
    os.log("Stivale2: Parsed devicetree blob!\n", .{});
  }

  for(info.memmap.?.get()) |*ent| {
    stivale.consume_physmem(ent);
  }

  const phys_high = stivale.phys_high(info.memmap.?.get());

  var context = os.vital(paging.bootstrap_kernel_paging(), "bootstrapping kernel paging");

  os.vital(os.memory.paging.map_physmem(.{
    .context = &context,
    .map_limit = phys_high,
  }), "Mapping physmem");

  os.memory.paging.kernel_context = context;
  platform.thread.bsp_task.paging_context = &os.memory.paging.kernel_context;

  context.apply();

  os.log("Doing vmm\n", .{});

  const heap_base = os.memory.paging.kernel_context.make_heap_base();

  os.vital(vmm.init(heap_base), "initializing vmm");

  os.log("Doing framebuffer\n", .{});

  if(info.framebuffer) |fb| {
    vesa_log.register_fb(vesa_log.lfb_updater, fb.addr, fb.pitch, fb.width, fb.height, fb.bpp);
  }
  else {
    vga_log.register();
  }

  os.log("Doing scheduler\n", .{});

  os.thread.scheduler.init(&platform.thread.bsp_task);

  os.log("Doing SMP\n", .{});

  if(info.smp) |smp| {
    const cpus = smp.get_writeback().get();

    os.platform.smp.init(cpus.len);

    var bootstrap_stack_size =
      os.memory.paging.kernel_context.page_size(0, os.memory.pmm.phys_to_uncached_virt(0));

    // Just a single page of stack isn't enough for debug mode :^(
    if(std.debug.runtime_safety) {
      bootstrap_stack_size *= 4;
    }

    // Allocate stacks for all CPUs
    var bootstrap_stack_pool_sz = bootstrap_stack_size * cpus.len;
    var stacks = os.vital(os.memory.pmm.alloc_phys(bootstrap_stack_pool_sz), "allocating ap stacks");

    // Setup counter used for waiting
    @atomicStore(usize, &os.platform.smp.cpus_left, cpus.len - 1, .Release);

    // Initiate startup sequence for all cores in parallel
    for(cpus) |*cpu_info, i| {
      const cpu = &os.platform.smp.cpus[i];

      cpu.acpi_id = cpu_info.acpi_proc_uid;

      if(i == 0)
        continue;

      cpu.booted = false;

      // Boot it!
      const stack = stacks + bootstrap_stack_size * i;

      cpu_info.argument = i;
      cpu_info.target_stack = os.memory.pmm.phys_to_write_back_virt(stack + bootstrap_stack_size - 16);
      @atomicStore(u64, &cpu_info.goto_address, @ptrToInt(smp_entry), .Release);
    }

    // Wait for the counter to become 0
    while (@atomicLoad(usize, &os.platform.smp.cpus_left, .Acquire) != 0) {
      os.platform.spin_hint();
    }

    // Free memory pool used for stacks. Unreachable for now
    os.memory.pmm.free_phys(stacks, bootstrap_stack_pool_sz);
    os.log("All cores are ready for tasks!\n", .{});
  }

  if(info.rsdp) |rsdp| {
    os.log("Registering rsdp: 0x{X}!\n", .{rsdp});
    platform.acpi.register_rsdp(rsdp);
  }

  os.vital(os.platform.platform_init(), "calling platform_init");

  kmain();
}
