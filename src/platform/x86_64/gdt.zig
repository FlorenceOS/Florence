pub const selector = .{
  .selnul = @as(u16, 0x00),
  .code64 = @as(u16, 0x08),
  .data64 = @as(u16, 0x10),
};

const gdt = [_]u64 {
  0x000F00000000FFFF, // Null
  0x00A09A0000000000, // 64 bit code
  0x0000920000000000, // 64 bit data

  0x00A09A0000000000 | (3 << 45), // Userspace 64 bit code
  0x0000920000000000 | (3 << 45), // Userspace 64 bit data
};

const Gdtr = packed struct {
  limit: u16,
  base: u64,
};

pub fn setup_gdt() void {
  const gdt_ptr = Gdtr {
    .limit = @sizeOf(u64) * gdt.len - 1,
    .base = @ptrToInt(&gdt[0]),
  };

  // Switch to the new descriptors
  asm volatile(
    \\  lgdt (%[p])
    \\  int $0x69
    \\  movw %[data64], %%ax
    \\  mov %%ax, %%ds
    \\  mov %%ax, %%fs
    \\  mov %%ax, %%gs
    \\  mov %%ax, %%es
    :
    : [data64] "X" (@as(u16, selector.data64))
    , [p] "X" (&gdt_ptr)
    : "rax"
  );
}
