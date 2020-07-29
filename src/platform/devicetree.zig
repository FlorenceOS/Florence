const log = @import("../logger.zig").log;
const std = @import("std");
const assert = std.debug.assert;

var parsed_dt: bool = false;

pub fn parse_dt(dt_data: ?[*]u8) !void {
  if(parsed_dt)
    return;

  parsed_dt = true;

  const effective_data: [*]u8 =
    if(dt_data != null) @ptrCast([*]u8, dt_data)
    else @intToPtr([*]u8, 0x40000000);

  try do_parse_dt(effective_data);
}

const read = std.mem.readIntBig;

fn do_parse_dt(dt_data: [*]u8) !void {
  const magic             = read(u32, dt_data[0x00 .. 0x04]);
  const totalsize         = read(u32, dt_data[0x04 .. 0x08]);
  const off_dt_struct     = read(u32, dt_data[0x08 .. 0x0C]);
  const off_dt_strings    = read(u32, dt_data[0x0C .. 0x10]);
  const off_mem_rsvmap    = read(u32, dt_data[0x10 .. 0x14]);
  const version           = read(u32, dt_data[0x14 .. 0x18]);
  const last_comp_version = read(u32, dt_data[0x18 .. 0x1C]);
  const boot_cpuid_phys   = read(u32, dt_data[0x1C .. 0x20]);
  const size_dt_strings   = read(u32, dt_data[0x20 .. 0x24]);
  const size_dt_struct    = read(u32, dt_data[0x24 .. 0x28]);

  assert(magic == 0xd00dfeed);

  log("Parsing DT\n");
}
