const log = @import("../logger.zig").log;
const hexdump = @import("../logger.zig").hexdump;

const pmm = @import("../pmm.zig");
const vmm = @import("../vmm.zig");
const paging = @import("../paging.zig");

const pci = @import("pci.zig");

const libalign = @import("../lib/align.zig");
const range = @import("../lib/range.zig");

const builtin = @import("builtin");
const std = @import("std");

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

fn locate_rsdp() !void {
  return error.locate_rsdp;
}

fn parse_MCFG(sdt: []u8) void {
  var offset: usize = 44;
  while(offset + 16 <= sdt.len): (offset += 16) {
    var   addr   = std.mem.readInt(u64, sdt[offset..][0..8],  builtin.endian);
    var   lo_bus = sdt[offset + 10];
    const hi_bus = sdt[offset + 11];

    while(true) {
      pci.register_mmio(lo_bus, addr) catch |err| {
        log("ACPI: Unable to register PCI mmio: {}\n", .{@errorName(err)});
      };

      if(lo_bus == hi_bus)
        break;

      addr += 1 << 20;
      lo_bus += 1;
    }
  }
}

fn sdt_size(sdt: anytype) u64 {
  return std.mem.readInt(u32, sdt[4..8], builtin.endian);
}

fn signature_value(sdt: anytype) u32 {
  return std.mem.readInt(u32, sdt[0..4], builtin.endian);
}

fn map_sdt(addr: u64) ![]u8 {
  const sdt = @ptrCast([*]u8, try paging.map_phys_struct([8]u8, addr, paging.data()));
  const sz = sdt_size(sdt);
  try paging.map_phys_size(addr, sz, paging.data());
  return sdt[0..sz];
}

fn parse_sdt(addr: usize) !void {
  const sdt = try map_sdt(addr);

  switch(signature_value(sdt)) {
    signature_value("FACP") => { }, // Ignore for now
    signature_value("SSDT") => { }, // Ignore for now
    signature_value("DMAR") => { }, // Ignore for now
    signature_value("ECDT") => { }, // Ignore for now
    signature_value("SBST") => { }, // Ignore for now
    signature_value("HPET") => { }, // Ignore for now
    signature_value("WAET") => { }, // Ignore for now
    signature_value("APIC") => {
      if(builtin.arch == .x86_64) {
        @import("x86_64/apic.zig").handle_madt(sdt);
      }
      else {
        log("ACPI: MADT found on non-x86 architecture!\n", .{});
      }
    },
    signature_value("MCFG") => {
      parse_MCFG(sdt);
    },
    else => {
      log("ACPI: Unknown SDT: '{s}' with size {} bytes\n", .{sdt[0..4], sdt.len});
      hexdump(sdt);
    },
  }
}

fn parse_root_sdt(comptime T: type, addr: usize) !void {
  const sdt = try map_sdt(addr);

  var offset: u64 = 36;

  while(offset + @sizeOf(T) <= sdt_size(sdt)): (offset += @sizeOf(T)) {
    try parse_sdt(std.mem.readInt(T, sdt[offset..][0..@sizeOf(T)], builtin.endian));
  }
}

pub fn init_acpi() !void {
  if(rsdp_phys == 0)
    try locate_rsdp();

  if(rsdp_phys == 0)
    return error.NoRSDP;

  rsdp = try paging.map_phys_struct(RSDP, rsdp_phys, paging.data());

  log("ACPI: Revision: {}\n", .{rsdp.revision});

  switch(rsdp.revision) {
    0 => try parse_root_sdt(u32, rsdp.rsdt_addr),
    2 => try parse_root_sdt(u64, rsdp.xsdt_addr),
    else => return error.UnknownACPIRevision,
  }
}
