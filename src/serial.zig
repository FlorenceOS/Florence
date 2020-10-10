const pmm = @import("pmm.zig");

var mmio32_serial: ?*volatile u32 = null;

pub fn register_mmio32_serial(phys: u64) void {
  if(mmio32_serial != null)
    @panic("Double mmio32 serial register");
  
  mmio32_serial = pmm.access_phys_single(u32, phys);
}

pub fn putch(ch: u8) void {
  if(mmio32_serial) |*s| {
    s.*.* = @as(u32, ch);
  }
}
