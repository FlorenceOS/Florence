pub const selector = .{
  .selnul = 0x00,
  .code16 = 0x08,
  .data16 = 0x10,
  .code32 = 0x18,
  .data32 = 0x20,
  .code64 = 0x28,
  .data64 = 0x30,
};

const gdt = &[_]u64 {
  0x000F00000000FFFF, // Null
  0x000F9A000000FFFF, // 16 bit code
  0x000F92000000FFFF, // 16 bit data
  0x00CF9A000000FFFF, // 32 bit code
  0x00CF92000000FFFF, // 32 bit data
  0x00A09A0000000000, // 64 bit code
  0x0000920000000000, // 64 bit data
};

const Gdtr = packed struct {
  limit: u16,
  base: u64,
};

pub fn setup_gdt() void {
  const gdt_ptr = Gdtr {
    .limit = @sizeOf(u64) * gdt.len - 1,
    .base = @ptrToInt(&gdt),
  };

  asm volatile(
    \\lgdt (%[p])
    :
    : [p] "r" (&gdt_ptr)
  );

  // Switch to the new descriptors
  asm volatile(
    \\mov %%rsp, %%rax
    \\push %[data64]
    \\push %%rax
    \\pushf
    \\push %[code64]
    \\push 1f
    \\iretq
    \\1:
    :
    : [data64] "N{dx}" (@as(u8, selector.data64))
    , [code64] "N{dx}" (@as(u8, selector.code64))
    : "rax"
  );
}