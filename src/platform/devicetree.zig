const os = @import("root").os;
const std = @import("std");
const assert = std.debug.assert;

var parsed_dt: bool = false;

pub fn parse_dt(dt_data: []u8) !void {
  if(parsed_dt)
    return;

  parsed_dt = true;

  var p = Parser { .data = dt_data };

  p.parse();
}

const readBig = std.mem.readIntBig;

const token = .{
  .begin_node = 0x00000001,
  .end_node   = 0x00000002,
  .prop       = 0x00000003,
  .nop        = 0x00000004,
  .end        = 0x00000009,
};

const Parser = struct {
  data: []const u8,
  curr_offset: u32 = 0,
  limit: u32 = undefined,

  fn readbytes(self: *Parser, comptime num_bytes: u32) *const [num_bytes]u8 {
    const old_offset = self.curr_offset;
    self.curr_offset += num_bytes;
    assert(self.curr_offset <= self.limit);
    return self.data[old_offset..][0..num_bytes];
  }

  fn read(self: *Parser, comptime t: type) t {
    return readBig(t, self.readbytes(@sizeOf(t)));
  }

  fn readstring(self: *Parser) []const u8 {
    const stroff = self.curr_offset;
    while(read(u8) != 0) { }
    return self.data[stroff .. self.curr_offset - 1];
  }

  pub fn parse(self: *Parser) void {
    assert(readBig(u32, self.data[0x00 .. 0x04]) == 0xd00dfeed); // Magic
    self.limit = readBig(u32, self.data[0x04 .. 0x08]); // Totalsize

    const off_dt_struct  = readBig(u32, self.data[0x08 .. 0x0C]);
    const off_mem_rsvmap = readBig(u32, self.data[0x10 .. 0x14]);

    //self.curr_offset = off_mem_rsvmap;
    //self.parse_resrved_regions();

    self.curr_offset = off_dt_struct;
    self.node(0);

    //os.log("DT has size {}\n", .{self.limit});

    // const off_dt_strings    = read(u32, dt_data[0x0C .. 0x10]);
    // const version           = read(u32, dt_data[0x14 .. 0x18]);
    // const last_comp_version = read(u32, dt_data[0x18 .. 0x1C]);
    // const boot_cpuid_phys   = read(u32, dt_data[0x1C .. 0x20]);
    // const size_dt_strings   = read(u32, dt_data[0x20 .. 0x24]);
    // const size_dt_struct    = read(u32, dt_data[0x24 .. 0x28]);
  }

  fn parse_resrved_regions(self: *Parser) void {
    os.log("Parsing reserved regions\n", .{});
    while(true) {
      os.log("{}\n", .{self});
      const addr = self.read(u64);
      const size = self.read(u64);
      if(addr == 0 and size == 0)
        continue;

      os.log("TODO: Reserved: {x} with size {x}", .{addr, size});
    }
  }

  fn node(self: *Parser, depth: usize) void {
    return; // We really don't care for now
  }

  pub fn format(self: *const Parser, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("Parser{{.data={X}, .offset={X}, limit={X}}}", .{@ptrToInt(self.data.ptr), self.curr_offset, self.limit});
  }

  fn parse_node(self: *Parser) void {

  }
};
