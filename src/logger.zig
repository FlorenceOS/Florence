const fmt = @import("std").fmt;
const platform = @import("platform.zig");
const serial = @import("serial.zig");

const Printer = struct {
 pub fn writeAll(self: *Printer, str: []const u8) !void {
   return print(str);
 }
 pub const Error = error{};
};

pub fn log(comptime format: []const u8, args: var) void {
  fmt.format(Printer{}, format, args) catch unreachable;
}

fn print(str: []const u8) !void {
  for(str) |c| {
    putch(c);
  }
}

fn putch(ch: u8) void {
  platform.debugputch(ch);
  serial.putch(ch);
}
