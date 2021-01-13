const os = @import("root").os;
const std = @import("std");
const builtin = @import("builtin");

const paging = os.memory.paging;

const range = os.lib.range.range;

pub const Handler = struct {
  function: fn(*os.platform.InterruptFrame, u64)void,
  context: u64
};

var handlers: [0x100]Handler = undefined;


pub const Addr = struct {
  bus: u8,
  device: u5,
  function: u3,

  pub fn format(self: *const Addr, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("[{x:0>2}:{x:0>2}:{x:0>1}]", .{self.bus, self.device, self.function});
  }
};

pub const Device = struct {
  addr: Addr,
  vendor_id: u16,
  device_id: u16,
  class: u8,
  subclass: u8,
  prog_if: u8,

  pub fn format(self: *const Device, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("{} ", .{self.addr});
    try writer.print("{{{x:0>4}:{x:0>4}}} ", .{self.vendor_id, self.device_id});
    try writer.print("({x:0>2}:{x:0>2}:{x:0>2})", .{self.class, self.subclass, self.prog_if});
  }
};

pub const regoff = u8;

fn mmio(addr: Addr, offset: regoff) [*]u8 {
  return @ptrCast([*]u8, pci_mmio[addr.bus].?) + (@as(u64, addr.device) << 15 | @as(u64, addr.function) << 12 | @as(u64, offset));
}

pub fn pci_read(comptime T: type, addr: Addr, offset: regoff) T {
  if(pci_mmio[addr.bus] != null)
    return std.mem.readIntNative(T, mmio(addr, offset)[0..@sizeOf(T)]);

  if(@hasDecl(os.platform, "pci_read"))
    return os.platform.pci_read(T, addr, offset);

  @panic("No pci_read method!");
}

pub fn pci_write(comptime T: type, addr: Addr, offset: regoff, value: T) void {
  if(pci_mmio[addr.bus] != null) {
    std.mem.writeIntNative(T, mmio(addr, offset)[0..@sizeOf(T)], value);
    return;
  }

  if(@hasDecl(os.platform, "pci_write"))
    return os.platform.pci_write(T, addr, offset, value);

  @panic("No pci_write method!");
}

const virtio_gpu = os.drivers.virtio_gpu;

fn function_scan(addr: Addr) void {
  const class = get_class(addr);
  const subclass = get_subclass(addr);
  const prog_if = get_prog_if(addr);

  const vendor_id = get_vendor_id(addr);
  const device_id = get_device_id(addr);

  if(vendor_id == 0xFFFF)
    return;

  const dev = Device {
    .addr = addr,
    .vendor_id = vendor_id,
    .device_id = device_id,
    .class = class,
    .subclass = subclass,
    .prog_if = prog_if,
  };

  os.log("PCI: {} ", .{dev});

  switch(class) {
    else => { os.log("Unknown class!\n", .{}); },
    0x00 => {
      switch(subclass) {
        else => { os.log("Unknown unclassified device!\n", .{}); },
      }
    },
    0x01 => {
      switch(subclass) {
        else => { os.log("Unknown storage controller!\n", .{}); },
        0x06 => {
          os.log("SATA controller\n", .{});
          os.drivers.ahci.register_controller(dev);
        },
      }
    },
    0x02 => {
      switch(subclass) {
        else => { os.log("Unknown network controller!\n", .{}); },
        0x00 => { os.log("Ethernet controller\n", .{}); },
        0x80 => { os.log("Other network controller\n", .{}); },
      }
    },
    0x03 => {
      if (vendor_id == 0x1AF4 or device_id == 0x1050) {
        os.log("Virtio display controller\n", .{});
        if (os.drivers.vesa_log.get_info()) |vesa| {
          var drv = virtio_gpu.Driver.init(addr) catch unreachable;
          drv.modeset(vesa.phys, vesa.width, vesa.height);
          drv.update_rect(.{.x = 0, .y = 0, .width = vesa.width, .height = vesa.height});
          os.drivers.vesa_log.set_updater(virtio_gpu.updater, @ptrToInt(&drv));
        }
      } else switch(subclass) {
        else => { os.log("Unknown display controller!\n", .{}); },
        0x00 => { os.log("VGA compatible controller\n", .{}); },
      }
    },
    0x04 => {
      switch(subclass) {
        else => { os.log("Unknown multimedia controller!\n", .{}); },
        0x03 => { os.log("Audio device\n", .{}); },
      }
    },
    0x06 => {
      switch(subclass) {
        else => { os.log("Unknown bridge device!\n", .{}); },
        0x00 => { os.log("Host bridge\n", .{}); },
        0x01 => { os.log("ISA bridge\n", .{}); },
        0x04 => { os.log("PCI-to-PCI bridge", .{});
          if((get_header_type(addr) & 0x7F) != 0x01) {
            os.log(": Not PCI-to-PCI bridge header type!\n", .{});
          }
          else {
            const secondary_bus = pci_read(u8, addr, 0x19);
            os.log(", recursively scanning bus {x:0>2}\n", .{secondary_bus});
            bus_scan(secondary_bus);
          }
        },
      }
    },
    0x0c => {
      switch(subclass) {
        else => { os.log("Unknown serial bus controller!\n", .{}); },
        0x03 => {
          switch(prog_if) {
            else => { os.log("Unknown USB controller!\n", .{}); },
            0x20 => { os.log("USB2 EHCI controller\n", .{}); },
            0x30 => {
              os.log("USB3 XHCI controller\n", .{});
            },
          }
        },
      }
    },
  }
}

pub fn get_vendor_id(addr: Addr) u16 {
  return pci_read(u16, addr, 0x00);
}

pub fn get_device_id(addr: Addr) u16 {
  return pci_read(u16, addr, 0x02);
}

fn get_header_type(addr: Addr) u8 {
  return pci_read(u8, addr, 0x0E);
}

fn get_class(addr: Addr) u8 {
  return pci_read(u8, addr, 0x0B);
}

fn get_subclass(addr: Addr) u8 {
  return pci_read(u8, addr, 0x0A);
}

fn get_prog_if(addr: Addr) u8 {
  return pci_read(u8, addr, 0x09);
}

fn device_scan(bus: u8, device: u5) void {
  const nullfunc = .{ .bus = bus, .device = device, .function = 0 };

  if(get_vendor_id(nullfunc) == 0xFFFF)
    return;

  function_scan(nullfunc);

  // Return already if this isn't a multi-function device
  if(get_header_type(nullfunc) & 0x80 == 0)
    return;

  inline for(range((1 << 3) - 1)) |function| {
    function_scan(.{ .bus = bus, .device = device, .function = function + 1 });
  }
}

fn bus_scan(bus: u8) void {
  inline for(range(1 << 5)) |device| {
    device_scan(bus, device);
  }
}

pub fn init_pci() !void {
  bus_scan(0);
}

pub fn register_mmio(bus: u8, physaddr: u64) !void {
  try paging.map_phys_size(physaddr, 1 << 20, paging.mmio(), null);
  pci_mmio[bus] = &os.memory.pmm.access_phys([1 << 20]u8, physaddr)[0];
}

var pci_mmio: [0x100]?*[1 << 20]u8 linksection(".bss") = undefined;

pub const PCI_OFFSET_VENDOR_ID = 0x00;
pub const PCI_OFFSET_DEVICE_ID = 0x02;
pub const PCI_OFFSET_COMMAND = 0x04;
pub const PCI_OFFSET_STATUS = 0x06;
pub const PCI_OFFSET_PROG_IF = 0x09;
pub const PCI_OFFSET_HEADER_TYPE = 0x0E;
pub const PCI_OFFSET_BASE_CLASS = 0x0B;
pub const PCI_OFFSET_SUB_CLASS = 0x0A;
pub const PCI_OFFSET_SECONDARY_BUS = 0x19;
pub const PCI_OFFSET_BAR0 = 0x10;
pub const PCI_OFFSET_BAR1 = 0x14;
pub const PCI_OFFSET_BAR2 = 0x18;
pub const PCI_OFFSET_BAR3 = 0x1C;
pub const PCI_OFFSET_BAR4 = 0x20;
pub const PCI_OFFSET_BAR5 = 0x24;
pub const PCI_OFFSET_CAP_PTR = 0x34;
pub const PCI_OFFSET_INT_LINE = 0x3C;
pub const PCI_OFFSET_INT_PIN = 0x3D;
