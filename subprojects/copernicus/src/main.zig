const std = @import("std");
const lib = @import("lib");

fn logStr(str: []const u8) void {
    _ = std.os.linux.write(2, str.ptr, str.len);
}

export fn _start() linksection(".text.entry") void {
    logStr("Hello, userspace!\n");
    std.os.linux.exit(0);
}
