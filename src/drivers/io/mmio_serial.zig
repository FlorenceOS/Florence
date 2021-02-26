const os = @import("root").os;

const reg_ptr = os.platform.phys_ptr(*volatile u32);

var mmio32_serial: ?reg_ptr = null;

var write_status: ?struct {
  status_ptr: reg_ptr,
  status_mask: u32,
  status_value: u32,
} = null;

pub fn register_mmio32_status_serial(uart_reg: u64, uart_status: u64, status_mask: u32, status_value: u32) void {
  if(mmio32_serial != null)
    @panic("Double mmio32 serial register");
  
  write_status = .{
    .status_ptr = reg_ptr.from_int(uart_reg),
    .status_mask = status_mask,
    .status_value = status_value,
  };

  register_mmio32_serial(uart_reg);
}

pub fn register_mmio32_serial(phys: u64) void {
  if(mmio32_serial != null)
    @panic("Double mmio32 serial register");
  
  mmio32_serial = reg_ptr.from_int(phys);
}

pub fn putch(ch: u8) void {
  if(ch == '\n')
    putch('\r');

  if(write_status) |s| {
    while((s.status_ptr.get().* & s.status_mask) != s.status_value) {
      os.platform.spin_hint();
    }
  }

  if(mmio32_serial) |reg| {
    reg.get().* = @as(u32, ch);
  }
}
