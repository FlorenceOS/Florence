const os = @import("root").os;

var mmio32_serial: ?*volatile u32 = null;
var write_status: ?struct {
  status_ptr: *volatile u32,
  status_mask: u32,
  status_value: u32,
} = null;

pub fn register_mmio32_status_serial(uart_reg: u64, uart_status: u64, status_mask: u32, status_value: u32) void {
  if(mmio32_serial != null)
    @panic("Double mmio32 serial register");
  
  write_status = .{
    .status_ptr = os.memory.pmm.access_phys_single(u32, uart_status),
    .status_mask = status_mask,
    .status_value = status_value,
  };

  register_mmio32_serial(uart_reg);
}

pub fn register_mmio32_serial(phys: u64) void {
  if(mmio32_serial != null)
    @panic("Double mmio32 serial register");
  
  mmio32_serial = os.memory.pmm.access_phys_single(u32, phys);
}

pub fn putch(ch: u8) void {
  if(write_status) |s| {
    while((s.status_ptr.* & s.status_mask) != s.status_value) {
      os.platform.spin_hint();
    }
  }

  if(mmio32_serial) |*s| {
    s.*.* = @as(u32, ch);
  }
}
