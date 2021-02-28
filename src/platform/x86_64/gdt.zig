pub const selector = .{
  .selnul = @as(u16, 0x00),
  .code64 = @as(u16, 0x08),
  .data64 = @as(u16, 0x10),
};
 
pub const Gdt = packed struct {
  const Gdtr = packed struct {
    limit: u16,
    base: u64,
  };
 
  descriptors: [5]u64 = [5]u64 {
    0x000F00000000FFFF, // Null
    0x00A09A0000000000, // 64 bit code
    0x0000920000000000, // 64 bit data
 
    0x00A09A0000000000 | (3 << 45), // Userspace 64 bit code
    0x0000920000000000 | (3 << 45), // Userspace 64 bit data
  },
 
  pub fn load(self: *@This()) void {
    const gdt_ptr = Gdtr {
      .limit = @sizeOf(Gdt) - 1,
      .base = @ptrToInt(self),
    };
 
  // Load the GDT
  asm volatile(
    \\  lgdt %[p]
    :
    : [p] "*p" (&gdt_ptr)
  );
 
  // Use the data selectors
  asm volatile(
    \\  mov %[dsel], %%ds
    \\  mov %[dsel], %%fs
    \\  mov %[dsel], %%gs
    \\  mov %[dsel], %%es
    \\  mov %[dsel], %%ss
    :
    : [dsel] "rm" (@as(u16, selector.data64))
  );
 
  // Use the code selector
  asm volatile(
    \\ push %[csel]
    \\ push $1f
    \\ .byte 0x48, 0xCB // Far return
    \\ 1:
    :
    : [csel] "i" (@as(u16, selector.code64))
  );
  }
};
