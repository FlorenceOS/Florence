pub const kernel = .{
  // Max number of CPU cores to use
  .max_cpus = 0x200,
  
  .x86_64 = .{
    // Allow using the `syscall` instruction to do syscalls
    .allow_syscall_instr = true,

    // The maximum number of IOAPICs to use
    .max_ioapics = 5,

    // Enable ps2 keyboard devices
    // Your system managment mode may emulate a ps2 keyboard
    // when you connect a usb keyboard. If you disable this,
    // that won't work.
    .enable_ps2_keyboard = true,
  },
};

pub const user = .{
  // The default keyboard layout
  .keyboard_layout = .en_US_QWERTY,
};
