const os = @import("root").os;

var mmio32_serial: ?u64 = null;
var write_status: ?struct {
  status_ptr: u64,
  status_mask: u32,
  status_value: u32,
} = null;

pub fn register_mmio32_status_serial(uart_reg: u64, uart_status: u64, status_mask: u32, status_value: u32) void {
  if(mmio32_serial != null)
    @panic("Double mmio32 serial register");
  
  write_status = .{
    .status_ptr = uart_status,
    .status_mask = status_mask,
    .status_value = status_value,
  };

  register_mmio32_serial(uart_reg);
}

pub fn register_mmio32_serial(phys: u64) void {
  if(mmio32_serial != null)
    @panic("Double mmio32 serial register");
  
  mmio32_serial = phys;
}

pub fn putch(ch: u8) void {
  if(write_status) |s| {
    const sptr = os.memory.pmm.access_phys_single_volatile(u32, s.status_ptr);
    while((sptr.* & s.status_mask) != s.status_value) {
      os.platform.spin_hint();
    }
  }

  if(mmio32_serial) |s| {
    const sptr = os.memory.pmm.access_phys_single_volatile(u32, s);
    sptr.* = @as(u32, ch);
  }
}
