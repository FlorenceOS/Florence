const platform_init = @import("../platform.zig").platform_init;
const kmain = @import("../kmain.zig").kmain;
const paging = @import("../paging.zig");

pub const os = @import("../os/kernel.zig");

export fn baremetal_virt_main() noreturn {
  try @import("../platform/devicetree.zig").parse_dt(@intToPtr([*]u8, 0x40000000));

  const paging_root = paging.bootstrap_kernel_paging();
  platform_init() catch unreachable;
  kmain();
}
