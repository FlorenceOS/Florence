const os = @import("root").os;
const pci = os.platform.pci;

const ata = @import("ata.zig");

var isa_controller_initialized = [1]bool{false} ** 6;

const drive = struct {
  supports_32: bool = false,
};

const Controller = struct {
  command: u16,
  control: u16,
  isaidx: ?u3,
  dev: ?pci.Device,

  drive0: ?drive = null,
  drive1: ?drive = null,

  pub fn read_ata_command(self: *const @This(), br: ata.command_reg) u8 {
    return os.platform.in(u8, @intCast(u16, self.command + @enumToInt(br)));
  }

  pub fn read_ata_control(self: *const @This(), br: ata.control_reg) u8 {
    return os.platform.in(u8, @intCast(u16, self.control + @enumToInt(br)));
  }

  pub fn write_ata_command(self: *const @This(), br: ata.command_reg, val: u8) void {
    os.platform.out(u8, @intCast(u16, self.command + @enumToInt(br)), val);
  }

  pub fn write_ata_control(self: *const @This(), br: ata.control_reg, val: u8) void {
    os.platform.out(u8, @intCast(u16, self.control + @enumToInt(br)), val);
  }

  pub fn wait_not_busy(self: *const @This()) void {
    while(self.read_ata_control(.alt_stat) & 0x80 != 0)
      os.thread.scheduler.yield();
  }

  pub fn attempt_init_drive(self: *@This(), num: u1, d: *?drive) void {
    self.write_ata_command(.drv_head, @as(u8, num) << 4);
    os.thread.scheduler.yield();
    self.write_ata_control(.dev_cntr, 1 << 2);
    os.thread.scheduler.yield();
    self.write_ata_control(.dev_cntr, 1 << 1);
    os.thread.scheduler.yield();

    self.wait_not_busy();

    if(self.read_ata_command(.error_) != 0)
      return;

    if(self.read_ata_command(.sect_cnt) != 1)
      return;

    if(self.read_ata_command(.sect_num) != 1)
      return;

    os.log("lba_high: 0x{X}\n", .{self.read_ata_command(.lba_high)});
    os.log("lba_mid:  0x{X}\n", .{self.read_ata_command(.lba_mid)});

    os.log("Drive {} looks healthy!\n", .{num});
  }

  pub fn init(self: *@This()) bool {
    self.attempt_init_drive(0, &self.drive0);
    self.attempt_init_drive(1, &self.drive1);

    return self.drive0 != null or self.drive1 != null;
  }

  pub fn controller_task(self: *@This()) !void {
    return;
  }
};

fn attempt_discovery(command: u16, control: u16, isaidx: ?u3, dev: ?pci.Device) void {
  if(isaidx) |idx| {
    if(isa_controller_initialized[idx])
      return;
    isa_controller_initialized[idx] = true;
  }

  var c: Controller = .{
    .command = command,
    .control = control,
    .isaidx = isaidx,
    .dev = dev,
  };

  if(c.init()) {
    os.thread.scheduler.make_task(Controller.controller_task, .{&c}) catch |err| {
      os.log("Error while starting IDE task: {}\n", .{@errorName(err)});
    };
  }
}

fn attempt_ports(command: u16, control: u16, dev: pci.Device) void {
  const idx: ?u3 = switch(command) {
    0x1F0 => 0,
    0x170 => 1,
    0x1E8 => 2,
    0x168 => 3,
    0x1E0 => 4,
    0x160 => 5,
    else => null,
  };
  attempt_discovery(command, control, idx, dev);
}

pub fn discover_controllers() void {
  os.log("IDE: Discovering ISA controllers\n", .{});
  attempt_discovery(0x1F0, 0x3F4, 0, null);
  attempt_discovery(0x170, 0x374, 1, null);
  attempt_discovery(0x1E8, 0x3EC, 2, null);
  attempt_discovery(0x168, 0x36C, 3, null);
  attempt_discovery(0x1E0, 0x3EC, 4, null);
  attempt_discovery(0x160, 0x36C, 5, null);
}

fn attempt_pci(dev: pci.Device, comptime idx: comptime_int) void {
  var command = pci.pci_read(u16, dev.addr, 0x10 + idx * 8);
  if(command & 1 == 0){
    os.log("IDE: Didn't get a port from PCI device, ignoring\n", .{});
    return;
  }
  attempt_ports(command & 0xFFFC, pci.pci_read(u16, dev.addr, 0x14 + idx * 8) & 0xFFFC, dev);
}

pub fn register_controller(dev: pci.Device) void {
  if(@import("builtin").arch != .x86_64) {
    os.log("IDE controller on non-x86!!\n", .{});
    return;
  }

  const supports_bus_mastering = dev.prog_if & 0x80 != 0;
  const mode: enum{isa, pci} = switch(dev.prog_if & 0x7F) {
    0x00, 0x0A => .isa,
    0x05, 0x0F => .pci,
    else => unreachable,
  };
  const mode_switchable = switch(dev.prog_if & 0x7F) {
    0x00, 0x05 => false,
    0x0A, 0x0F => true,
    else => unreachable,
  };

  if(supports_bus_mastering)
    pci.pci_write(u32, dev.addr, 0x4, pci.pci_read(u32, dev.addr, 0x4) | (0x5 << 1));

  attempt_pci(dev, 0);
  attempt_pci(dev, 1);
}
