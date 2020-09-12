const log = @import("../logger.zig").log;
const hexdump = @import("../logger.zig").hexdump;

const pmm = @import("../pmm.zig");
const vmm = @import("../vmm.zig");
const paging = @import("../paging.zig");

const page_size = @import("../platform.zig").page_sizes[0];

const pci = @import("pci.zig");

const libalign = @import("../lib/align.zig");

var rsdp_phys: usize = 0;
var rsdp: *RSDP = undefined;

pub fn register_rsdp(rsdp_in: usize) void {
  rsdp_phys = rsdp_in;
}

fn locate_rsdp() !void {
  return error.todo;
}

fn parse_xsdt() !void {

}

fn parse_rsdt() !void {

}

const RSDP = struct {
  signature: [8]u8,
  checksum: u8,
  oemid: [6]u8,
  revision: u8,
  rsdt_addr: u32,

  extended_length: u32,
  xsdt_addr: u64,
  extended_checksum: u8,
};

pub fn init_acpi() !void {
  if(rsdp_phys == 0)
    try locate_rsdp();

  if(rsdp_phys == 0)
    return error.NoRSDP;

  const rsdp_max_size = @sizeOf(RSDP);

  const rsdp_page_low = libalign.align_down(usize, page_size, rsdp_phys);
  const rsdp_page_high = libalign.align_up(usize, page_size, rsdp_phys + rsdp_max_size);

  try paging.map_phys_range(rsdp_page_low, rsdp_page_high, paging.data());
  rsdp = &pmm.access_phys(RSDP, rsdp_phys)[0];

  log("ACPI revision: {}\n", .{rsdp.revision});

  // hexdump(@ptrCast([*]u8, rsdp)[0..@sizeOf(RSDP)]);
}
