const os = @import("root").os;
const std = @import("std");
const builtin = @import("builtin");

const log = os.log;

const pci = os.platform.pci;

const paging    = os.memory.paging;
const pmm       = os.memory.pmm;
const scheduler = os.thread.scheduler;
const page_size = os.platform.page_sizes[0];

const Mutex = scheduler.Mutex;

const abar_size = 0x1100;
const port_control_registers_size = 0x80;

const bf = os.lib.bitfields;

const Port = packed struct {
  command_list_base: u64,
  fis_base: u64,
  interrupt_status: u32,
  interrupt_enable: u32,
  command_status: u32,
  reserved_0x1C: u32,
  task_file_data: u32,
  signature: u32,
  sata_status: u32,
  sata_control: u32,
  sata_error: u32,
  sata_active: u32,
  command_issue: u32,
  sata_notification: u32,
  fis_switching_control: u32,
  device_sleep: u32,
  reserved_0x48: [0x70-0x48]u8,
  vendor_0x70: [0x80-0x70]u8,

  pub fn command_headers(self: *const volatile @This()) *volatile [32]CommandTableHeader {
    return &pmm.access_phys_single_volatile(CommandList, self.command_list_base).command_headers;
  }
};

comptime {
  std.debug.assert(@sizeOf(Port) == 0x80);
}

const handoff_bios_busy  = 1 << 4;
const handoff_os_owned   = 1 << 1;
const handoff_bios_owned = 1 << 0;

const ahci_version = extern union {
  value: u32,

  major:      bf.bitfield(u32, 16, 16),
  minor_high: bf.bitfield(u32, 8, 8),
  minor_low:  bf.bitfield(u32, 0, 8),

  pub fn format(self: *const ahci_version, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("{}.{}", .{self.major.read(), self.minor_high.read()});
    if(self.minor_low.read() != 0)
      try writer.print(".{}", .{self.minor_low.read()});
  }
};

const abar_handoff = extern union {
  value: u32,
  bios_owned: bf.boolean(u32, 4),
  ownership:  bf.boolean(u32, 3),
  os_owned:   bf.boolean(u32, 1),
  bios_busy:  bf.boolean(u32, 0),

  fn set_handoff(self: *volatile @This()) void {
    self.os_owned.write(true);
  }

  fn check_handoff(self: *volatile @This()) bool {
    if(self.bios_owned.read())
      return false;

    if(self.bios_busy.read())
      return false;

    if(self.os_owned.read())
      return true;

    return false;
  }

  fn try_claim(self: *volatile @This()) bool {
    self.set_handoff();
    const success = self.check_handoff();
    if(success)
      self.ownership.write(true);
    return success;
  }
};

comptime {
  std.debug.assert(@sizeOf(abar_handoff) == 4);
  std.debug.assert(@bitSizeOf(abar_handoff) == 32);
}

const ABAR = struct {
  hba_capabilities: u32,
  global_hba_control: u32,
  interrupt_status: u32,
  ports_implemented: u32,
  version: ahci_version,
  command_completion_coalescing_control: u32,
  command_completion_coalescing_port: u32,
  enclosure_managment_location: u32,
  enclosure_managment_control: u32,
  hba_capabilities_extended: u32,
  bios_handoff: abar_handoff,
  reserved_0x2C: u32,
  reserved_0x30: [0xA0-0x30]u8,
  vendor_0xA0: [0x100-0xA0]u8,
  ports: [32]Port,
};

comptime {
  std.debug.assert(@sizeOf(ABAR) == 0x1100);
}

fn claim_controller(abar: *volatile ABAR) void {
  {
    const version = abar.version;
    log("AHCI: Version: {}\n", .{version});

    if(version.major.read() < 1 or version.minor_high.read() < 2) {
      log("AHCI: Handoff not supported (version)\n", .{});
      return;
    }
  }

  if(abar.hba_capabilities & 1 == 0) {
    log("AHCI: Handoff not supported (capabilities)\n", .{});
    return;
  }

  while(!abar.bios_handoff.try_claim()) {
    scheduler.yield();
  }

  log("AHCI: Got handoff!\n", .{});
}

const sata_port_type = enum {
  ata,
  atapi,
  semb,
  pm,
};

const status_start: u32 = 0x00000001;
const status_command_list_running: u32 = 0x00008000;
const status_receive_enable: u32 = 0x00000010;

fn send_command(port: *volatile Port, slot: u5) void {
  log("AHCI: Sending command in slot {} to port 0x{X}\n", .{slot, @ptrToInt(port)});

  while((port.task_file_data & (0x88)) != 0) // Transfer busy or data transfer requested
    scheduler.yield();

  port.command_status &= ~status_start;

  while(port.command_status & status_command_list_running != 0)
    scheduler.yield();

  port.command_status |= status_receive_enable;
  port.command_status |= status_start;

  const slot_bit = @as(u32, 1) << slot;

  port.command_issue |= slot_bit;

  while(port.command_issue & slot_bit != 0)
    scheduler.yield();

  port.command_status &= ~status_start;

  while(port.command_status & status_command_list_running != 0)
    scheduler.yield();

  port.command_status &= ~status_receive_enable;

  log("AHCI: Port 0x{X}: Command sent!\n", .{@ptrToInt(port)});
}

const CommandTableHeader = packed struct {
  command_fis_length: u5,
  atapi: u1,
  write: u1,
  prefetchable: u1,

  sata_reset_control: u1,
  bist: u1,
  clear: u1,
  _res1_3: u1,
  pmp: u4,

  pdrt_count: u16,
  command_table_byte_size: u32,
  command_table_addr: u64,
  reserved: [4]u32,

  pub fn table(self: *volatile @This()) *volatile CommandTable {
    return pmm.access_phys_single_volatile(CommandTable, self.command_table_addr);
  }
};

comptime {
  std.debug.assert(@sizeOf(CommandTableHeader) == 0x20);
}

const CommandList = struct {
  command_headers: [32]CommandTableHeader,
};

const RecvFis = struct {
  dma_setup: [0x1C]u8,
  _res1C: [0x20 - 0x1C]u8,

  pio_setup: [0x14]u8,
  _res34: [0x40 - 0x34]u8,

  d2h_register: [0x14]u8,
  _res54: [0x58 - 0x54]u8,

  set_device_bits: [8]u8,

  unknown_fis: [0x40]u8,
  _resA0: [0x100 - 0xA0]u8,
};

comptime {
  std.debug.assert(@byteOffsetOf(RecvFis, "dma_setup") == 0);
  std.debug.assert(@byteOffsetOf(RecvFis, "pio_setup") == 0x20);
  std.debug.assert(@byteOffsetOf(RecvFis, "d2h_register") == 0x40);
  std.debug.assert(@byteOffsetOf(RecvFis, "set_device_bits") == 0x58);
  std.debug.assert(@byteOffsetOf(RecvFis, "unknown_fis") == 0x60);
  std.debug.assert(@sizeOf(RecvFis) == 0x100);
}

const PRD = packed struct {
  data_base_addr: u64,
  _res08: u32,
  sizem1: u22,
  _res10_22: u9,
  completion_interrupt: u1,
};

comptime {
  std.debug.assert(@sizeOf(PRD) == 0x10);
}

const FisH2D = packed struct {
  fis_type: u8 = 0x27,
  pmport: u4,
  _res1_4: u3,
  c: u1,

  command: u8,
  feature_low: u8,

  lba_low: u24,
  device: u8,

  lba_high: u24,
  feature_high: u8,

  count: u16,
  icc: u8,
  control: u8,
};

comptime {
  std.debug.assert(@byteOffsetOf(FisH2D, "command") == 2);
}

const CommandFis = extern union {
  bytes: [0x40]u8,
  cmd: FisH2D,
};

const CommandTable = struct {
  command_fis: CommandFis,
  atapi_command: [0x10]u8,
  _res50: [0x80 - 0x50]u8,
  // TODO: Maybe more(?)
  // First buffer should always be pointing to a single preallocated page
  // when this command table is unused. Make sure to restore it if you overwrite it
  prds: [8]PRD,
};

comptime {
  std.debug.assert(@sizeOf(CommandTable) == 0x100);
}

fn command(port: *volatile Port, slot: u5) void {

}

fn command_with_buffer(port: *volatile Port, slot: u5, buf: usize, bufsize: usize) void {
  const header = &port.command_headers()[slot];
  //const oldbuf = header.;
  //const oldsize = ;
}

fn sata_port_task(comptime port_type: sata_port_type, port: *volatile Port) !void {
  if(port_type != .ata)
    return;

  log("AHCI: {} task started for port at 0x{X}\n", .{@tagName(port_type), @ptrToInt(port)});

  // Set up command buffers
  {
    if(port.command_list_base == 0 or port.fis_base == 0) {
      const port_io_size = @sizeOf(CommandList) + @sizeOf(RecvFis);

      const commands_phys = try pmm.alloc_phys(port_io_size);
      const fis_phys = commands_phys + @sizeOf(CommandList);

      try paging.map_phys_size(commands_phys, port_io_size, paging.mmio(), null);
      @memset(pmm.access_phys_volatile(u8, commands_phys), 0, port_io_size);

      port.command_list_base = commands_phys;
      port.fis_base = fis_phys;
    } else {
      try paging.map_phys_size(port.command_list_base, @sizeOf(CommandList), paging.mmio(), null);
      try paging.map_phys_size(port.fis_base, @sizeOf(RecvFis), paging.mmio(), null);
    }
  }

  // Preallocate and set up command tables
  {
    var current_table_addr: usize = undefined;
    var reamining_table_size: usize = 0;

    for(port.command_headers()) |*header| {
      if(reamining_table_size < @sizeOf(CommandTable)) {
        reamining_table_size = page_size;
        current_table_addr = try pmm.alloc_phys(page_size);
        try paging.map_phys_size(current_table_addr, page_size, paging.mmio(), null);
        @memset(pmm.access_phys_volatile(u8, current_table_addr), 0, page_size);
      }

      header.command_table_addr = current_table_addr;
      header.pdrt_count = 1;
      header.command_fis_length = @sizeOf(FisH2D) / @sizeOf(u32);
      header.atapi = if(port_type == .atapi) 1 else 0;
      current_table_addr   += @sizeOf(CommandTable);
      reamining_table_size -= @sizeOf(CommandTable);

      // First PRD is just a small preallocated single page buffer
      const buf = try pmm.alloc_phys(page_size);
      try paging.map_phys_size(buf, page_size, paging.mmio(), null);
      @memset(pmm.access_phys_volatile(u8, buf), 0, page_size);
      header.table().prds[0].data_base_addr = buf;
      header.table().prds[0].sizem1 = page_size - 1;
    }
  }

  // Port is now ready to be used on all command slots
  {
    log("AHCI: Identifying drive...\n", .{});

    const header = &port.command_headers()[0];
    const table = header.table();
    const identify_fis = &table.command_fis.cmd;

    identify_fis.command =
      switch(port_type) {
        .ata   => 0xEC,
        .atapi => 0xA1,
        else => unreachable,
      };

    identify_fis.c = 1;
    identify_fis.device = 0;

    os.hexdump_obj(header);
    log("\n", .{});
    os.hexdump_obj(table);

    asm volatile("":::"memory");

    send_command(port, 0);

    asm volatile("":::"memory");

    var i: usize = 0;
    while(i < 1000000): (i += 1) {
      scheduler.yield();
    }

    os.hexdump(pmm.access_phys(u8, table.prds[0].data_base_addr)[0..512]);
  }
}

fn controller_task(abar: *volatile ABAR) !void {
  claim_controller(abar);

  log("AHCI: Claimed controller.\n", .{});

  const ports_implemented = abar.ports_implemented;

  for(abar.ports) |*port, i| {
    if((ports_implemented >> @intCast(u5, i)) & 1 == 0)
      continue;

    {
      const sata_status = port.sata_status;

      {
        const com_status = sata_status & 0xF;

        if(com_status == 0)
          continue;

        if(com_status != 3) {
          log("AHCI: Warning: Unknown port com_status: {}\n", .{com_status});
          continue;
        }
      }

      {
        const ipm_status = (sata_status >> 8) & 0xF;

        if(ipm_status != 1) {
          log("AHCI: Warning: Device sleeping: {}\n", .{ipm_status});
          continue;
        }
      }
    }

    switch(port.signature) {
      0x00000101 => try scheduler.make_task(sata_port_task, .{.ata,   port}),
      0xEB140101 => try scheduler.make_task(sata_port_task, .{.atapi, port}),
      0xC33C0101,
      0x96690101 => {
        log("Known TODO port signature: 0x{X}\n", .{port.signature});
        //scheduler.make_task(sata_port_task, .{.semb,   port})
        //scheduler.make_task(sata_port_task, .{.pm,     port})
      },
      else => {
        log("Unknown port signature: 0x{X}\n", .{port.signature});
        return;
      },
    }
  }
}

pub fn register_controller(dev: pci.Device) void {
  // Busty master bit
  pci.pci_write(u32, dev.addr, 0x4, pci.pci_read(u32, dev.addr, 0x4) | (0x6 << 1));

  const abar_phys = pci.pci_read(u32, dev.addr, 0x24) & 0xFFFFF000;

  log("AHCI: Got abar phys: 0x{X}\n", .{abar_phys});

  paging.map_phys_size(abar_phys, abar_size, paging.mmio(), null) catch |err| {
    log("AHCI: Failed to map ABAR: {}\n", .{@errorName(err)});
  };

  const abar = pmm.access_phys_single_volatile(ABAR, abar_phys);
  log("AHCI: ABAR is accessible at 0x{X}\n", .{@ptrToInt(abar)});

  const cap = abar.hba_capabilities;

  log("AHCI: HBA capabilities: 0x{X}\n", .{cap});

  if((cap & (1 << 31)) == 0) {
    log("AHCI: Controller is 32 bit only, ignoring.\n", .{});
    return;
  }

  if(abar.global_hba_control & (1 << 31) == 0) {
    log("AHCI: AE not set!\n", .{});
    return;
  }

  scheduler.make_task(controller_task, .{abar}) catch |err| {
    log("AHCI: Failed to make controller task: {}\n", .{@errorName(err)});
  };
}
