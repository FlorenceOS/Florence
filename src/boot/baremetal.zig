const platform_init = @import("../platform.zig").platform_init;
const kmain = @import("../kmain.zig").kmain;

pub const os = @import("../os/kernel.zig");

export fn baremetal_main() void {
  platform_init() catch unreachable;
  kmain() catch unreachable;
}
