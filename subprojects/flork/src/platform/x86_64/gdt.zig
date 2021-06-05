const Tss = @import("tss.zig").Tss;

pub const selector = .{
    .selnul = @as(u16, 0x00),
    .code64 = @as(u16, 0x08),
    .data64 = @as(u16, 0x10),
    .usercode64 = @as(u16, 0x18 | 3),
    .userdata64 = @as(u16, 0x20 | 3),
    .tss = @as(u16, 0x28),
};

pub const Gdt = packed struct {
    const Gdtr = packed struct {
        limit: u16,
        base: u64,
    };

    descriptors: [7]u64 = [7]u64{
        0x0000000000000000, // Null
        0x00A09A0000000000, // 64 bit code
        0x0000920000000000, // 64 bit data
        0x00A09A0000000000 | (3 << 45), // Userspace 64 bit code
        0x0000920000000000 | (3 << 45), // Userspace 64 bit data
        // Reserved for TSS
        0,
        0,
    },

    fn set_tss_address(self: *@This(), tss: *Tss) void {
        self.descriptors[5] = ((@sizeOf(Tss) - 1) & 0xffff) |
            ((@ptrToInt(tss) & 0xffffff) << 16) |
            (0b1001 << 40) | (1 << 47) |
            (((@ptrToInt(tss) >> 24) & 0xff) << 56);
        self.descriptors[6] = @ptrToInt(tss) >> 32;
    }

    pub fn update_tss(self: *@This(), tss: *Tss) void {
        self.set_tss_address(tss);
        asm volatile (
            \\ltr %[ts_sel]
            :
            : [ts_sel] "r" (@as(u16, selector.tss))
        );
    }

    pub fn load(self: *@This()) void {
        const gdt_ptr = Gdtr{
            .limit = @sizeOf(Gdt) - 1,
            .base = @ptrToInt(self),
        };

        // Load the GDT
        asm volatile (
            \\  lgdt %[p]
            :
            : [p] "*p" (&gdt_ptr)
        );

        // Use the data selectors
        asm volatile (
            \\  mov %[dsel], %%ds
            \\  mov %[dsel], %%fs
            \\  mov %[dsel], %%gs
            \\  mov %[dsel], %%es
            \\  mov %[dsel], %%ss
            :
            : [dsel] "rm" (@as(u16, selector.data64))
        );

        // Use the code selector
        asm volatile (
            \\ push %[csel]
            \\ push $1f
            \\ .byte 0x48, 0xCB // Far return
            \\ 1:
            :
            : [csel] "i" (@as(u16, selector.code64))
        );
    }
};
