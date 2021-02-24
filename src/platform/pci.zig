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

pub const Cap = struct {
  addr: Addr,
  off: u8, 
  pub fn next(self: *Cap) void { self.off = self.addr.read(u8, self.off + 0x01); }
  pub fn vndr(self: *const Cap) u8 { return self.addr.read(u8, self.off + 0x00); }
  pub fn read(self: *const Cap, comptime T: type, off: regoff) T { return self.addr.read(T, self.off + off); }
  pub fn write(self: *const Cap, comptime T: type, off: regoff, value: T) void { self.addr.write(T, self.off + off, value); }
};

pub const Addr = struct {
  bus: u8,
  device: u5,
  function: u3,

  const vendor_id = cfgreg(u16, 0x00);
  const device_id = cfgreg(u16, 0x02);
  const command = cfgreg(u16, 0x04);
  const status = cfgreg(u16, 0x06);
  const prog_if = cfgreg(u8, 0x09);
  const header_type = cfgreg(u8, 0x0E);
  const base_class = cfgreg(u8, 0x0B);
  const sub_class = cfgreg(u8, 0x0A);
  const secondary_bus = cfgreg(u8, 0x19);
  const cap_ptr = cfgreg(u8, 0x34);
  const int_line = cfgreg(u8, 0x3C);
  const int_pin = cfgreg(u8, 0x3D);
  
  pub fn cap(self: Addr) Cap { return .{ .addr = self, .off = self.cap_ptr().read() & 0xFC }; }

  pub fn barinfo(self: Addr, bar_idx: u8) BarInfo {
    var orig: u64 = self.read(u32, 0x10 + bar_idx * 4) & 0xFFFFFFF0;
    self.write(u32, 0x10 + bar_idx * 4 , 0xFFFFFFFF);
    var pci_out = self.read(u32, 0x10 + bar_idx * 4);
    const is64 = ((pci_out & 0b110) >> 1) == 2; // bits 1:2, bar type (0 = 32bit, 1 = 64bit)

    // The BARs can be either 64 or 32 bit, but the trick works for both
    var response: u64 = @as(u64, pci_out & 0xFFFFFFF0) | 0xFFFFFFFF00000000; 
    if (is64) {
      orig |= @as(u64, self.read(u32, 0x14 + bar_idx * 4)) << 32;
      self.write(u32, 0x10 + bar_idx * 4, 0xFFFFFFFF); // 64bit bar = two 32-bit bars 
      response |= @as(u64, self.read(u32, 0x14 + bar_idx * 4)) << 32;
      self.write(u32, 0x14 + bar_idx * 4, @truncate(u32, orig >> 32));
    }
    self.write(u32, 0x10 + bar_idx * 4 , @truncate(u32, orig));
    return .{.phy = orig, .size = ~response + 1};
  }

  pub fn read(self: Addr, comptime T: type, offset: regoff) T {
    if(pci_mmio[self.bus] != null)
      return std.mem.readIntLittle(T, mmio(self, offset)[0..@sizeOf(T)]);
    if(@hasDecl(os.platform, "pci_read"))
      return os.platform.pci_read(T, self, offset);
    @panic("No pci_read method!");
  }

  pub fn write(self: Addr, comptime T: type, offset: regoff, value: T) void {
    if(pci_mmio[self.bus] != null) {
      std.mem.writeIntLittle(T, mmio(self, offset)[0..@sizeOf(T)], value);
      return;
    }
    if(@hasDecl(os.platform, "pci_write"))
        return os.platform.pci_write(T, self, offset, value);
    @panic("No pci_write method!");
  }


  pub fn format(self: Addr, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("[{x:0>2}:{x:0>2}:{x:0>1}]", .{self.bus, self.device, self.function});
    try writer.print("{{{x:0>4}:{x:0>4}}} ", .{self.vendor_id().read(), self.device_id().read()});
    try writer.print("({x:0>2}:{x:0>2}:{x:0>2})", .{self.base_class().read(), self.sub_class().read(), self.prog_if().read()});
  }
};

pub const regoff = u8;

fn mmio(addr: Addr, offset: regoff) [*]u8 {
  return @ptrCast([*]u8, pci_mmio[addr.bus].?) + (@as(u64, addr.device) << 15 | @as(u64, addr.function) << 12 | @as(u64, offset));
}

const virtio_gpu = os.drivers.virtio_gpu;


const BarInfo = struct {
  phy: u64,
  size: u64,
};

fn function_scan(addr: Addr) void {
  if(addr.vendor_id().read() == 0xFFFF)
    return;

  os.log("PCI: {} ", .{addr});

  switch(addr.base_class().read()) {
    else => { os.log("Unknown class!\n", .{}); },
    0x00 => {
      switch(addr.sub_class().read()) {
        else => { os.log("Unknown unclassified device!\n", .{}); },
      }
    },
    0x01 => {
      switch(addr.sub_class().read()) {
        else => { os.log("Unknown storage controller!\n", .{}); },
        0x06 => {
          os.log("SATA controller\n", .{});
          os.drivers.ahci.register_controller(addr);
        },
      }
    },
    0x02 => {
      switch(addr.sub_class().read()) {
        else => { os.log("Unknown network controller!\n", .{}); },
        0x00 => { os.log("Ethernet controller\n", .{}); },
        0x80 => { os.log("Other network controller\n", .{}); },
      }
    },
    0x03 => {
      if (addr.vendor_id().read() == 0x1AF4 or addr.device_id().read() == 0x1050) {
        os.log("Virtio display controller\n", .{});
        if (os.drivers.vesa_log.get_info()) |vesa| {
          const ephemeral = os.memory.vmm.backed(.Eternal);
          const drv = ephemeral.create(virtio_gpu.Driver) catch {
            os.log("Virtio display controller: Allocation failure\n", .{});
            return;
          };
          drv.* = virtio_gpu.Driver.init(addr) catch {
            os.log("Virtio display controller: Init has failed!\n", .{});
            return;
          };
          drv.modeset(vesa.phys, vesa.width, vesa.height);
          drv.update_rect(.{.x = 0, .y = 0, .width = vesa.width, .height = vesa.height});
          os.drivers.vesa_log.set_updater(virtio_gpu.updater, @ptrToInt(drv));
        }
      } else switch(addr.sub_class().read()) {
        else => { os.log("Unknown display controller!\n", .{}); },
        0x00 => { os.log("VGA compatible controller\n", .{}); },
       }
    },
    0x04 => {
      switch(addr.sub_class().read()) {
        else => { os.log("Unknown multimedia controller!\n", .{}); },
        0x03 => { os.log("Audio device\n", .{}); },
      }
    },
    0x06 => {
      switch(addr.sub_class().read()) {
        else => { os.log("Unknown bridge device!\n", .{}); },
        0x00 => { os.log("Host bridge\n", .{}); },
        0x01 => { os.log("ISA bridge\n", .{}); },
        0x04 => { os.log("PCI-to-PCI bridge", .{});
          if((addr.header_type().read() & 0x7F) != 0x01) {
            os.log(": Not PCI-to-PCI bridge header type!\n", .{});
          }
          else {
            const secondary_bus = addr.secondary_bus().read();
            os.log(", recursively scanning bus {x:0>2}\n", .{secondary_bus});
            bus_scan(secondary_bus);
          }
        },
      }
    },
    0x0c => {
      switch(addr.sub_class().read()) {
        else => { os.log("Unknown serial bus controller!\n", .{}); },
        0x03 => {
          switch(addr.prog_if().read()) {
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

fn device_scan(bus: u8, device: u5) void {
  const nullfunc: Addr = .{ .bus = bus, .device = device, .function = 0 };

  if(nullfunc.vendor_id().read() == 0xFFFF)
    return;

  function_scan(nullfunc);

  // Return already if this isn't a multi-function device
  if(nullfunc.header_type().read() & 0x80 == 0)
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
  try paging.remap_phys_size(.{
    .phys = physaddr,
    .size = 1 << 20,
    .memtype = .DeviceUncacheable,
  });
  pci_mmio[bus] = &os.memory.pmm.access_phys([1 << 20]u8, physaddr)[0];
}

var pci_mmio: [0x100]?*[1 << 20]u8 linksection(".bss") = undefined;

fn PciFn(comptime T: type, comptime off: regoff) type {
  return struct {
    self: Addr,
    pub fn read(self: @This()) T { return self.self.read(T, off); }
    pub fn write(self: @This(), val: T) void { self.self.write(T, off, val); }
  };
}

fn cfgreg(comptime T: type, comptime off: regoff) fn(self:Addr) PciFn(T, off) {
  return struct {
    fn function(self: Addr) PciFn(T, off) { return .{ .self = self }; }
  }.function;
}

pub const PCI_CAP_MSIX_MSGCTRL = 0x02;
pub const PCI_CAP_MSIX_TABLE = 0x04;
pub const PCI_CAP_MSIX_PBA = 0x08;

pub const PCI_COMMAND_BUSMASTER = 1<<2;
pub const PCI_COMMAND_LEGACYINT_DISABLE = 1<<10;
