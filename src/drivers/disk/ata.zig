pub const command_reg = extern enum {
  data = 0,
  error_ = 1,
  features = 1,
  sect_cnt = 2,

  sect_num = 3,
  lba_low = 3,

  cyl_low = 4,
  lba_mid = 4,

  cyl_high = 5,
  lba_high = 5,

  drv_head = 6,
  status = 7,
  command = 7,
};

pub const control_reg = extern enum {
  alt_stat = 2,
  dev_cntr = 2,
  drv_addr = 3,
};
