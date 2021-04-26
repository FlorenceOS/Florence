const os = @import("root").os;
const builtin = @import("builtin");
const std = @import("std");

const paging = os.memory.paging;
const pci    = os.platform.pci;

const libalign = os.lib.libalign;
const range    = os.lib.range;

const RSDP = packed struct {
  signature: [8]u8,
  checksum: u8,
  oemid: [6]u8,
  revision: u8,
  rsdt_addr: u32,

  extended_length: u32,
  xsdt_addr: u64,
  extended_checksum: u8,
};

var rsdp_phys: usize = 0;
var rsdp: *RSDP = undefined;

pub fn register_rsdp(rsdp_in: usize) void {
  rsdp_phys = rsdp_in;
}

fn locate_rsdp() ?u64 {
  // @TODO
  return null;
}

fn parse_MCFG(sdt: []u8) void {
  var offset: usize = 44;
  while(offset + 16 <= sdt.len): (offset += 16) {
    var   addr   = std.mem.readInt(u64, sdt[offset..][0..8],  builtin.endian);
    var   lo_bus = sdt[offset + 10];
    const hi_bus = sdt[offset + 11];

    while(true) {
      pci.register_mmio(lo_bus, addr) catch |err| {
        os.log("ACPI: Unable to register PCI mmio: {}\n", .{@errorName(err)});
      };

      if(lo_bus == hi_bus)
        break;

      addr += 1 << 20;
      lo_bus += 1;
    }
  }
}

fn signature_value(sdt: anytype) u32 {
  return std.mem.readInt(u32, sdt[0..4], builtin.endian);
}

fn get_sdt(addr: u64) []u8 {
  var result = os.platform.phys_slice(u8).init(addr, 8);
  result.len = std.mem.readInt(u32, result.to_slice_writeback()[4..8], builtin.endian);
  return result.to_slice_writeback();
}

fn parse_sdt(addr: usize) void {
  const sdt = get_sdt(addr);

  switch(signature_value(sdt)) {
    signature_value("FACP") => { }, // Ignore for now
    signature_value("SSDT") => { }, // Ignore for now
    signature_value("DMAR") => { }, // Ignore for now
    signature_value("ECDT") => { }, // Ignore for now
    signature_value("SBST") => { }, // Ignore for now
    signature_value("HPET") => { }, // Ignore for now
    signature_value("WAET") => { }, // Ignore for now
    signature_value("SPCR") => { }, // Ignore for now
    signature_value("GTDT") => { }, // Ignore for now
    signature_value("APIC") => {
      switch(builtin.arch) {
        .x86_64 => @import("x86_64/apic.zig").handle_madt(sdt),
        else => os.log("ACPI: MADT found on unsupported architecture!\n", .{}),
      }
    },
    signature_value("MCFG") => {
      parse_MCFG(sdt);
    },
    else => {
      os.log("ACPI: Unknown SDT: '{s}' with size {} bytes\n", .{sdt[0..4], sdt.len});
    },
  }
}

fn parse_root_sdt(comptime T: type, addr: usize) void {
  const sdt = get_sdt(addr);

  var offset: u64 = 36;

  while(offset + @sizeOf(T) <= sdt.len): (offset += @sizeOf(T)) {
    parse_sdt(std.mem.readInt(T, sdt[offset..][0..@sizeOf(T)], builtin.endian));
  }
}

pub fn init_acpi() !void {
  if(rsdp_phys == 0)
    rsdp_phys = locate_rsdp() orelse return;

  rsdp = os.platform.phys_ptr(*RSDP).from_int(rsdp_phys).get_writeback();

  os.log("ACPI: Revision: {}\n", .{rsdp.revision});

  switch(rsdp.revision) {
    0 => parse_root_sdt(u32, rsdp.rsdt_addr),
    2 => parse_root_sdt(u64, rsdp.xsdt_addr),
    else => return error.UnknownACPIRevision,
  }
}
