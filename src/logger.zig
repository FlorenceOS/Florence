const fmt = @import("std").fmt;
const platform = @import("platform.zig");
const serial = @import("serial.zig");
const range = @import("lib/range.zig");
const arch = @import("builtin").arch;

const Printer = struct {
  pub fn writeAll(self: *const Printer, str: []const u8) !void {
    try @call(.{.modifier = .never_inline}, print_str, .{str});
  }

  pub fn print(self: *const Printer, comptime format: []const u8, args: anytype) !void {
    log(format, args);
  }

  pub fn writeByteNTimes(self: *const Printer, val: u8, num: usize) !void {
    var i: usize = 0;
    while(i < num): (i += 1) {
      putch(val);
    }
  }

  pub const Error = anyerror;
};

pub fn log(comptime format: []const u8, args: anytype) void {
  var printer = Printer{};
  fmt.format(printer, format, args) catch unreachable;
}

fn print_str(str: []const u8) !void {
  for(str) |c| {
    putch(c);
  }
}

fn putch(ch: u8) void {
  platform.debugputch(ch);
  serial.putch(ch);
  @import("drivers/vesa_log.zig").putch(ch);
  if(arch == .x86_64) {
    @import("drivers/vga_log.zig").putch(ch);
  }
}

pub fn hexdump(in_bytes: []const u8) void {
  var bytes = in_bytes;
  while(bytes.len != 0) {
    log("{x:0^16}: ", .{@ptrToInt(&bytes[0])});

    inline for(range.range(0x10)) |offset| {
      if(offset < bytes.len) {
        const value = bytes[offset];
        log("{x:0^2} ", .{value});
      } else {
        log("   ", .{});
      }
    }

    inline for(range.range(0x10)) |offset| {
      if(offset < bytes.len) {
        const value = bytes[offset];
        if(0x20 <= value and value < 0x7F) {
          log("{c}", .{value});
        } else {
          log(".", .{});
        }
      } else {
        log(" ", .{});
      }
    }

    log("\n", .{});

    if(bytes.len < 0x10)
      return;

    bytes = bytes[0x10..];
  }
}
