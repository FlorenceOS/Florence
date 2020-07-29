const init_interrupts = @import("interrupts.zig").init_interrupts;
const setup_gdt = @import("gdt.zig").setup_gdt;

pub const page_sizes =
  [_]u64 {
    0x1000,
    0x200000,
    0x40000000,
  };

pub fn platform_init() !void {
  setup_gdt();
  try init_interrupts();
}

pub fn outb(port: u16, val: u8) void {
  asm volatile (
    "outb %[val], %[port]"
    :
    : [val] "{al}"(val), [port] "N{dx}"(port)
  );
}

pub fn inb(port: u16) u8 {
  return asm volatile (
    "inb %[port], %[result]"
    : [result] "={al}" (-> u8)
    : [port]   "N{dx}" (port)
  );
}

pub fn debugputch(ch: u8) void {
  outb(0xe9, ch);
}
