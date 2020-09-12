const log = @import("../logger.zig").log;
const hexdump = @import("../logger.zig").hexdump;

const pmm = @import("../pmm.zig");
const vmm = @import("../vmm.zig");
const paging = @import("../paging.zig");

const pci = @import("pci.zig");

const libalign = @import("../lib/align.zig");
const range = @import("../lib/range.zig");

const apic = @import("x86_64/apic.zig");

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

pub const SDT = struct {
  signature: [4]u8,
  length: u32,
  revision: u8,
  checksum: u8,
  oem_id: [6]u8,
  oem_table_id: [8]u8,
  oem_revision: u32,
  creator_id: u32,
  creator_revision: u32,

  fn signature_value(self: *const @This()) u32 {
    return make_signature(self.signature[0..4]);
  }
};

var rsdp_phys: usize = 0;
var rsdp: *RSDP = undefined;

pub fn register_rsdp(rsdp_in: usize) void {
  rsdp_phys = rsdp_in;
}

fn locate_rsdp() !void {
  return error.todo;
}

fn make_signature(signature: []const u8) u32 {
  var result: u32 = undefined;
  const rp = @ptrCast(*[4]u8, &result);
  for(signature) |c, i| {
    rp[i] = c;
  }
  return result;
}

fn report_MCFG_pci_mmio(addr_in: u64, low: u8, high: u8) void {
  var addr = addr_in;

  var current_bus: u8 = 0;

  while(true) {
    pci.register_mmio(current_bus, addr) catch |err| {
      log("Unable to register PCI mmio: {}\n", .{@errorName(err)});
    };
    // End condition is like this in case high == 255 and we overflow
    if(current_bus == high)
      break;
    current_bus += 1;
    addr += 1 << 20;
  }
}

fn parse_MCFG_pci_mmio(sdt: *SDT, offset: usize) void {
  const sdtp = @ptrCast([*]u8, sdt) + offset;
  const addr = std.mem.readInt(u64, sdtp[0..8], builtin.endian);
  //report_MCFG_pci_mmio(addr, sdtp[10], sdtp[11]);
}

fn parse_sdt(addr: usize) !void {
  const sdt = try paging.map_phys_struct(SDT, addr, paging.data());
  try paging.map_phys_size(addr, sdt.length, paging.data());
  
  switch(sdt.signature_value()) {
    make_signature("FACP") => { }, // Ignore for now
    make_signature("SSDT") => { }, // Ignore for now
    make_signature("DMAR") => { }, // Ignore for now
    make_signature("ECDT") => { }, // Ignore for now
    make_signature("SBST") => { }, // Ignore for now
    make_signature("HPET") => { }, // Ignore for now
    make_signature("APIC") => {
      if(builtin.arch == .x86_64) {
        apic.handle_madt(sdt);
      }
      else {
        log("ACPI: MADT found on non-x86 architecture!\n", .{});
      }
    },
    make_signature("MCFG") => {
      var offset: usize = 44;
      while(offset + 16 <= sdt.length) {
        parse_MCFG_pci_mmio(sdt, offset);
        offset += 16;
      }
    },
    else => {
      log("ACPI: Unknown SDT: '{s}' with size {} bytes\n", .{sdt.signature, sdt.length});
      hexdump(@ptrCast([*]u8, sdt)[0..sdt.length]);
    }
  }
}

fn parse_root_sdt(comptime T: type, addr: usize) !void {
  const sdt = try paging.map_phys_struct(SDT, addr, paging.data());
  try paging.map_phys_size(addr, sdt.length, paging.data());

  const num_entries = (sdt.length - @sizeOf(SDT))/@sizeOf(T);
  const table = @ptrCast([*]u8, sdt) + @sizeOf(SDT);

  var entry_ind: u64 = 0;
  while(entry_ind < num_entries) {
    var entry: u64 = 0;
    @memcpy(@ptrCast([*]u8, &entry), table + entry_ind * @sizeOf(T), @sizeOf(T));
    try parse_sdt(entry);
    entry_ind += 1;
  }
}

pub fn init_acpi() !void {
  if(rsdp_phys == 0)
    try locate_rsdp();

  if(rsdp_phys == 0)
    return error.NoRSDP;

  rsdp = try paging.map_phys_struct(RSDP, rsdp_phys, paging.data());

  log("ACPI revision: {}\n", .{rsdp.revision});

  if(rsdp.revision == 0)
    try parse_root_sdt(u32, rsdp.rsdt_addr);
  if(rsdp.revision == 2)
    try parse_root_sdt(u64, rsdp.xsdt_addr);
}
